require 'pry'
require 'pry-remote-em'
require 'fiber'
require 'pry-remote-em/json-proto'

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
    end

    def post_init
      @lines = []
      Pry.config.pager, @old_pager = false, Pry.config.pager
      Pry.config.system, @old_system = PryRemoteEm::Server::System, Pry.config.system
      # TODO authenticate user https://github.com/simulacre/pry-remote-em/issues/5
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] received client connection from #{ip}:#{port}"
      send_data({:g => "PryRemoteEm #{VERSION} #{@opts[:tls] ? 'pryems' : 'pryem'}"})
      start_tls if @opts[:tls]
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] ssl connection established"
    end

    def start_tls
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def unbind
      Pry.config.pager = @old_pager
      Pry.config.system = @old_system
      Kernel.puts "[pry-remote-em] remote session terminated"
    end

    def receive_json(j)
      if j['d']
        @lines.push(*j['d'].split("\n"))
        if @waiting
          f, @waiting = @waiting, nil
          f.resume(@lines.shift)
        end
      elsif j['c']
        send_data({:c => @compl_proc.call(j['c'])})
      else
        warn "received unexpected data: #{j.inspect}"
      end # j['d']
    end # receive_json(j)

    def readline(prompt)
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

    System = proc do |output, cmd, _|
      output.puts("shell commands are not yet supported")
    end
  end # module::Server
end # module::PryRemoteEm
