require 'pry'
require 'pry-remote-em'
# How it works with Pry
#
# When PryRemoteEm.run is called it registers with EventMachine for a given ip
# and port. When a connection is received EM yields an instance of PryRemoteEm,
# we start a Fiber (f1) then call Pry.start specifying the Server instance as the
# input and output object for Pry. The Pry instance that is created goes into
# its REPL.  When it gets to the read part it calls @input.readline
# (PryRemoteEm#readline) and passes a prompt, e.g., [1] pry(#<Foo>)>.
#
# PryRemoteEm#readline calls #send_data with the prompt then yields from the
# current Fiber (f1); the one we started when EventMachine yielded to us. The root
# Fiber is now active again. At some point, the root Fiber receives data from
# the client. It calls #receive_data in our Server instance. That instance then
# resumes the Fiber (f1) that was waiting for #readline to finish.
#
# Inside the resumed Fiber (f1) PryRemoteEm#readline returns the recieved data
# to the instance of Pry, which continues its REPL. Pry calls #puts, or #print
# or #write on its output object (PryRemoteEm). We send that data out to the client
# and immediately return. Pry then calls PryRemoteEm#readline again and again
# we send the prompt then immediately yield back to the root Fiber.
#
# Pry just interacts with PryRemoteEm as if it were any other blocking Readline
# object. The important bit is making sure that it is started in a new Fiber that
# can be paused and resumed as needed. PryRemoteEm#readline pauses it and
# PryRemoteEm#receive_json resumes it.
#
# Reference:
# http://www.igvita.com/2010/03/22/untangling-evented-code-with-ruby-fibers/

module PryRemoteEm
  module Server
    include JsonProto

    class << self
      def run(obj, host = DEFHOST, port = DEFPORT, opts = {:tls => false})
        tries = :auto == port ? 100.tap{ port = DEFPORT } : 1
        # TODO raise a useful exception not RuntimeError
        raise "root permission required for port below 1024 (#{port})" if port < 1024 && Process.euid != 0
        begin
          EM.start_server(host, port, PryRemoteEm::Server, opts) do |pre|
            Fiber.new {
              begin
                Pry.start(obj, :input => pre, :output => pre)
              ensure
                pre.close_connection
              end
            }.resume
          end
        rescue => e
          # EM 1.0.0.beta4's message tells us the port is in use; 0.12.10 just says, 'no acceptor'
          if (e.message.include?('port is in use') || e.message.include?('no acceptor')) && tries >= 1
            tries -= 1
            port += 1
            retry
          end
          raise e
        end
        scheme = opts[:tls] ? 'pryems' : 'pryem'
        Kernel.puts "[pry-remote-em] listening for connections on #{scheme}://#{host}:#{port}/"
      end # run(obj, host = DEFHOST, port = DEFPORT)
    end # class << self

    def initialize(opts = {:tls => false})
      @after_auth = []
      @opts       = opts
      if (a = opts[:auth])
        if a.respond_to?(:call)
          return fail("auth handler procs must take two arguments not (#{a.method(:call).arity})") unless a.method(:call).arity == 2
          @auth = a
        else
          return error("auth handler objects must respond to :call, or :[]") unless a.respond_to?(:[])
          @auth = lambda {|u,p| a[u] && a[u] == p }
        end
        @auth_tries = 5
      end
    end

    def post_init
      @lines = []
      Pry.config.pager, @old_pager = false, Pry.config.pager
      Pry.config.system, @old_system = PryRemoteEm::Server::System, Pry.config.system
      @auth_required  = @auth
      port, ip        = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] received client connection from #{ip}:#{port}"
      send_data({:g => "PryRemoteEm #{VERSION} #{@opts[:tls] ? 'pryems' : 'pryem'}"})
      @opts[:tls] ? start_tls : (@auth_required && send_data({:a => false}))
    end

    def start_tls
      Kernel.puts "[pry-remote-em] starting TLS (#{peer_ip}:#{peer_port})"
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established (#{peer_ip}:#{peer_port})"
      send_data({:a => false}) if @auth_required
    end

    def peer_ip
      return @peer_ip if @peer_ip
      return "" if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_ip
    end

    def peer_port
      return @peer_port if @peer_port
      return "" if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_port
    end

    def receive_json(j)
      return send_data({:a => false}) if @auth_required && !j['a']

      if j['d'] # just normal data
        @lines.push(*j['d'].split("\n"))
        if @waiting
          f, @waiting = @waiting, nil
          f.resume(@lines.shift)
        end
      elsif j['c'] # tab completion request
        send_data({:c => @compl_proc.call(j['c'])})

      elsif j['a'] # authentication response
        return send_data({:a => true}) if !@auth || !@auth_required
        return send_data({:a => 'auth data must be a two element array'}) unless j['a'].is_a?(Array) && j['a'].length == 2
        unless (@auth_required = !@auth.call(*j['a']))
          authenticated!
        else
          if @auth_tries <= 0
            msg = "max authentication attempts reached"
            send_data({:a => msg})
            Kernel.puts "[pry-remote-em] #{msg} (#{peer_ip}:#{peer_port})"
            return close_connection_after_writing
          end
          @auth_tries -= 1
        end
        return send_data({:a => !@auth_required})

      else
        warn "received unexpected data: #{j.inspect}"
      end # j['d']
    end # receive_json(j)


    def authenticated!
      while (aa = @after_auth.shift)
        send_data(aa)
      end
    end

    def unbind
      Pry.config.pager  = @old_pager
      Pry.config.system = @old_system
      Kernel.puts "[pry-remote-em] remote session terminated (#{peer_ip}:#{peer_port})"
    end

    # Methods that make Server compatible with Pry

    def readline(prompt)
      @auth_required ? @after_auth.push({:p => prompt}) : send_data({:p => prompt})
      return @lines.shift unless @lines.empty?
      @waiting = Fiber.current
      return Fiber.yield
    end

    def print(val)
      send_data({:d => val})
    end
    alias :write :print

    def puts(data = "")
      s = data.to_s
      print(s[0] == "\n" ? s : s + "\n")
    end

    def completion_proc=(compl)
      @compl_proc = compl
    end

    def tty?
      true # might be a very bad idea ....
    end

    def flush
      true
    end

    System = proc do |output, cmd, _|
      output.puts("shell commands are not yet supported")
    end
  end # module::Server
end # module::PryRemoteEm
