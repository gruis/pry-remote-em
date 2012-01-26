require 'pry'
require 'pry-remote-em'

module PryRemoteEm
  module Server
    include JsonProto

    class << self
      def run(obj, host = DEFHOST, port = DEFPORT, opts = {:tls => false})
        tries = :auto == port ? 100.tap{ port = DEFPORT } : 1
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
          if e.message.include?('port is in use') && tries >= 1
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
      @opts = opts
      if (a = opts[:auth])
        if a.respond_to?(:call)
          return error("auth handler procs must take two arguments") unless a.method(:call).arity == 2
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
      start_tls if @opts[:tls]
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established (#{peer_ip}:#{peer_port})"
    end

    def start_tls
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def unbind
      Pry.config.pager = @old_pager
      Pry.config.system = @old_system
      Kernel.puts "[pry-remote-em] remote session terminated (#{peer_ip}:#{peer_port})"
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
        if (@auth_required = !@auth.call(*j['a']))
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

    def readline(prompt)
      # @todo don't send the prompt until authed if auth required
      send_data({:p => prompt})
      return @lines.shift unless @lines.empty?
      @waiting = Fiber.current
      return Fiber.yield
    end

    # Methods that make Server compatible with Pry

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

    def tty?
      true # might be a very bad idea ....
    end

    System = proc do |output, cmd, _|
      output.puts("shell commands are not yet supported")
    end
  end # module::Server
end # module::PryRemoteEm
