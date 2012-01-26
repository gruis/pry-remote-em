require 'uri'
require 'pry-remote-em'
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
      @user = opts[:user]
      @pass = opts[:pass]
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
      if j['p'] # prompt
        if @negotiated && !@unbound
          # Is it better just to wrap receive_data in a Fiber?
          Fiber.new {
            op = lambda {
              true until !(l = Readline.readline(j['p'], true)).empty?
              l
            }
            cb = lambda { |l| send_data(l) }
            EM.defer(op, cb)
          }.resume
        end

      elsif j['d'] # printable data
        print j['d']

      elsif j['g'] # server banner
        Kernel.puts "[pry-remote-em] remote is #{j['g']}"
        name, version, scheme = j['g'].split(" ", 3)
        # TODO parse version and compare against a Gem style matcher
        if version == PryRemoteEm::VERSION
          if scheme.nil? || scheme != (reqscheme = @opts[:tls] ? 'pryems' : 'pryem')
            return fail("[pry-remote-em] server doesn't support requried scheme #{reqscheme.dump}")
          end
          @nego_timer.cancel
          @negotiated = true
          !@opts[:tls] ? authenticate : Kernel.puts("[pry-remote-em] negotiating TLS").tap { start_tls }
        else
          fail("[pry-remote-em] incompatible version #{version}")
        end

      elsif j['c'] # tab completion response
        @waiting, f = nil, @waiting
        f.resume(j['c']) if f

      elsif j.include?('a') # authentication demand
        return fail j['a'] if j['a'].is_a?(String)
        return authenticate if j['a']   == false
        @authenticated = true if j['a'] == true

      else
        warn "[pry-remote-em] received unexpected data: #{j.inspect}"
      end
    end

    def authenticate
      return fail("[pry-remote-em] user and pass required for authentication") unless @user && @pass
      return fail("[pry-remote-em] can't authenticate before negotiation complete") unless @negotiated
      send_data({:a => [@user, @pass]})
    end # authenticate

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established"
      authenticate
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
