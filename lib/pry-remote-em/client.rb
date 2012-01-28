require 'uri'
require 'pry-remote-em'
require 'pry/helpers/base_helpers'
#require "readline"   # doesn't work with Fiber.yield
        #  - /Users/caleb/src/pry-remote-em/lib/pry-remote-em/client.rb:45:in `yield': fiber called across stack rewinding barrier (FiberError)
require "rb-readline" # doesn't provide vi-mode support :(
        # https://github.com/luislavena/rb-readline/issues/21
        # https://github.com/simulacre/rb-readline/commit/0376eb4e9526b3dc1a6512716322efcef409628d

module PryRemoteEm
  module Client
    include EM::Deferrable
    include JsonProto
    include Pry::Helpers::BaseHelpers

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
      if (a = opts[:auth])
        if a.respond_to?(:call)
          @auth = a
        else
          @auth = lambda { a }
        end
      end
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
          Fiber.new { send_data(Readline.readline(j['p'], true)) }.resume
        end

      elsif j['d'] # printable data
        stagger_output j['d'], $stdout # Pry::Helpers::BaseHelpers

      elsif j['g'] # server banner
        Kernel.puts "[pry-remote-em] remote is #{j['g']}"
        name, version, scheme = j['g'].split(" ", 3)
        # TODO parse version and compare against a Gem style matcher
        return fail("[pry-remote-em] incompatible version #{version}") if version != PryRemoteEm::VERSION
        if scheme.nil? || scheme != (reqscheme = @opts[:tls] ? 'pryems' : 'pryem')
          if scheme == 'pryems' && defined?(::OpenSSL)
            @opts[:tls] = true
          else
            return fail("[pry-remote-em] server doesn't support requried scheme #{reqscheme.dump}")
          end # scheme == 'pryems' && defined?(::OpenSSL)
        end
        @nego_timer.cancel
        @negotiated = true
        start_tls if @opts[:tls]

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
      return fail("[pry-remote-em] authentication required") unless @auth
      return fail("[pry-remote-em] can't authenticate before negotiation complete") unless @negotiated
      user, pass = @auth.call
      return fail("[pry-remote-em] expected #{@auth} to return a user and password") unless user && pass
      send_data({:a => [user, pass]})
    end # authenticate

    def ssl_handshake_completed
      Kernel.puts "[pry-remote-em] TLS connection established"
    end

    def start_tls
      Kernel.puts "[pry-remote-em] negotiating TLS"
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def unbind
      @unbound = true
      Kernel.puts "[pry-remote-em] session terminated"
      error? ? fail : succeed
    end
  end # module::Client
end # module::PryRemoteEm

# Pry::Helpers::BaseHelpers#stagger_output expects Pry.pager to be defined
class Pry
  class << self
    attr_accessor :pager unless respond_to?(:pager)
  end
end
Pry.pager = true
