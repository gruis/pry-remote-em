require 'readline'
require 'uri'
require 'pry-remote-em'

module PryRemoteEm
  module Client
    include EM::Deferrable

    def initialize(opts = {})
      @opts = opts
    end

    def post_init
      @buffer  = ""
      return fail("connection was not established") unless get_peername
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] client connected to pryem://#{ip}:#{port}/"
      @nego_timer = EM::Timer.new(PryRemoteEm::NEGOTIMER) do
        fail("[pry-remote-em] server didn't finish negotiation within #{PryRemoteEm::NEGOTIMER} seconds; terminating")
      end
    end

    def connection_completed
      # if @opts[:tls]
      #   Kernel.puts "[pry-remote-em] negotiating TLS"
      #   start_tls
      # end
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established"
    end

    def receive_data(d)
      return unless d && d.length > 0
      if six = d.index(PryRemoteEm::DELIM)
        @buffer << d[0...six]
        j = JSON.load(@buffer)
        @buffer.clear
        receive_json(j)
        receive_data(d[(six + PryRemoteEm::DELIM.length)..-1])
      else
        @buffer << d
      end
    end

    def receive_json(j)
      if j['p']
        send_data(Readline.readline(j['p'], true) + "\n") if @negotiated && !@unbound

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
        else
          fail("incompatible version")
        end

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
