module PryRemoteEm
  module Client
    module Broker
      include PryRemoteEm::Proto
      include EM::Deferrable

      def initialize(opts);
        @opts = opts
      end

      def receive_banner(name, version, scheme)
        return fail("[pry-remote-em broker-client] incompatible version #{version}") if version != PryRemoteEm::VERSION
        if scheme.nil? || scheme != (reqscheme = @opts[:tls] ? 'pryems' : 'pryem')
          if scheme == 'pryems' && defined?(::OpenSSL)
            @opts[:tls] = true
          else
            return fail("[pry-remote-em broker-client] server doesn't support required scheme #{reqscheme.dump}")
          end
        end
        @opts[:tls] ? start_tls : succeed(self)
      end

      def log
        return @opts[:logger] if @opts[:logger]
        @log ||= Logger.new(STDERR)
      end

      def start_tls
        return if @tls_started
        @tls_started = true
        super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
      end

      def ssl_handshake_completed
        succeed(self)
      end

      def unbind
        log.info("[pry-remote-em broker-client] broker connection unbound starting a new one")
        # Give the existing broker a little time to release the port. Even if the restart
        # here fails the next time a server tries to register, a new client will be
        # created; when that fails Broker#restart will be called again.
        EM::Timer.new(rand(0.9)) do
          PryRemoteEm::Broker.restart(@opts[:tls])
        end
      end

    end # module::Broker
  end # module::Client
end # module::PryRemoteEm
