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
            return fail("[pry-remote-em broker] server doesn't support required scheme #{reqscheme.dump}")
          end
        end
        @opts[:tls] ? start_tls : succeed(self)
      end

      def start_tls
        return if @tls_started
        @tls_started = true
        super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
      end

      def ssl_handshake_completed
        succeed(self)
      end

    end # module::Broker
  end # module::Client
end # module::PryRemoteEm
