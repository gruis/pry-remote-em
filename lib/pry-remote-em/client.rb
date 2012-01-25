require 'readline'
require 'uri'
require 'pry-remote-em'
require 'pry-remote-em/json-proto'
require "fiber"

module PryRemoteEm
  module Client
    include EM::Deferrable
    include JsonProto

    def initialize(opts = {})
      @opts = opts
    end

    def post_init
      return fail("connection was not established") unless get_peername
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] client connected to pryem://#{ip}:#{port}/"
      @nego_timer = EM::Timer.new(PryRemoteEm::NEGOTIMER) do
        fail("[pry-remote-em] server didn't finish negotiation within #{PryRemoteEm::NEGOTIMER} seconds; terminating")
      end
    end

    def connection_active
      Readline.completion_proc = lambda do |str|
        @waiting = Fiber.current
        send_data({:c => str})
        return Fiber.yield
      end
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established"
    end

    def receive_json(j)
      if j['p']
        if @negotiated && !@unbound
          send_data(Readline.readline(j['p'], true))
        end

      elsif j['d']
        print j['d']

      elsif j['g']
        Kernel.puts "[pry-remote-em] remote is #{j['g']}"
        name, version, scheme = j['g'].split(" ", 3)
        # TODO parse version and compare against a Gem style matcher
        if version == PryRemoteEm::VERSION
          if scheme.nil? || scheme != (reqscheme = @opts[:tls] ? 'pryems' : 'pryem')
            return fail("[pry-remote-em] server doesn't support requried scheme #{reqscheme.dump}")
          end
          @nego_timer.cancel
          @negotiated = true
          Kernel.puts("[pry-remote-em] negotiating TLS").tap { start_tls } if @opts[:tls]
          connection_active
        else
          fail("incompatible version")
        end

      elsif j['c']
        @waiting, f = nil, @waiting
        Fiber.new { f.resume(j['c']) }.resume if f

      else
        warn "received unexpected data: #{j}"
      end
    end

    def start_tls
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def unbind
      @unbound = true
      Kernel.puts "[pry-remote-em] session terminated"
      error? ? fail : succeed
    end
  end # module::Client
end # module::PryRemoteEm
