require "pry-remote-em/proto"

module PryRemoteEm
  module Client
    module Generic
      include EM::Deferrable
      include Proto

      def initialize(opts = {})
        @opts   = opts
      end

      def opts
        @opts ||= {}
      end

      def log
        @log ||= Class.new do
          def print(str); $stderr.puts(str) end
          alias :info :print
          alias :warn :print
          alias :error :print
          alias :debug :print
        end.new
      end

      def start_tls
        return if @tls_started
        @tls_started = true
        log.info("[pry-remote-em] negotiating TLS")
        super(opts[:tls].is_a?(Hash) ? opts[:tls] : {})
      end

      def connection_completed
        if get_peername
          port, ip = Socket.unpack_sockaddr_in(get_peername)
          log.info("[pry-remote-em] client connected to pryem://#{ip}:#{port}/")
        else
          # TODO use the args used to create this connection
          log.info("[pry-remote-em] client connected")
        end
        @nego_timer = EM::Timer.new(PryRemoteEm::NEGOTIMER) do
          fail("[pry-remote-em] server didn't finish negotiation within #{PryRemoteEm::NEGOTIMER} seconds; terminating")
        end
      end

      def receive_banner(name, version, scheme)
        log.info("[pry-remote-em] remote is #{name} #{version} #{scheme}")
        client_ver = Gem::Version.new(PryRemoteEm::VERSION)
        server_req = Gem::Requirement.new("~>#{version}")
        server_ver = Gem::Version.new(version)
        client_req = Gem::Requirement.new("~>#{PryRemoteEm::VERSION}")
        unless server_req.satisfied_by?(client_ver) || client_req.satisfied_by?(server_ver)
          fail("[pry-remote-em] incompatible version #{PryRemoteEm::VERSION}")
          return false
        end
        if scheme.nil? || scheme != (reqscheme = opts[:tls] ? 'pryems' : 'pryem')
          if scheme == 'pryems' && defined?(::OpenSSL)
            opts[:tls] = true
          else
            fail("[pry-remote-em] server doesn't support required scheme #{reqscheme.dump}")
            return false
          end
        end
        @negotiated = true
        @nego_timer.cancel
        true
      end


    end # module::Generic
  end # module::Client
end # module::PryRemoteEm
