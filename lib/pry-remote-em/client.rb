require 'uri'
require 'pry-remote-em'
require 'pry-remote-em/json-proto'
require "fiber"
#require "readline"   # doesn't work with Fiber.yield
#  - /Users/caleb/src/pry-remote-em/lib/pry-remote-em/client.rb:45:in `yield': fiber called across stack rewinding barrier (FiberError)
require "rb-readline" # doesn't provide vi-mode support :(
                      # https://github.com/luislavena/rb-readline/issues/21

module PryRemoteEm
  module Client
    include EM::Deferrable
    include JsonProto

    class << self
      def start(host = PryRemoteEm::DEFHOST, port = PryRemoteEM::DEFPORT, opts = {:tls => false})
        EM.connect(host || PryRemoteEm::DEFHOST, port || PryRemoteEm::DEFPORT, PryRemoteEm::Client, opts) do |c|
          c.callback { yield if block_given? }
          c.errback do |e|
            puts "[pry-remote-em] connection failed\n#{e}"
            yield(e) if block_given?
          end
        end
      end
    end # class << self

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
      Readline.completion_proc = method(:auto_complete)
    end

    def auto_complete(word)
      @waiting = Fiber.current
      send_data({:c => word})
      return Fiber.yield
    end

    def receive_json(j)
      if j['p']
        if @negotiated && !@unbound
          # Is it better just to wrap receive_data in a Fiber?
          Fiber.new { send_data(Readline.readline(j['p'], true)) }.resume
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
        else
          fail("incompatible version")
        end

      elsif j['c']
        @waiting, f = nil, @waiting
        f.resume(j['c']) if f

      else
        warn "received unexpected data: #{j}"
      end
    end

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established"
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
