require 'pry-remote-em/client/generic'

module PryRemoteEm
  module Client
    module Broker
      include Client::Generic
      include EM::Deferrable

      def log
        return opts[:logger] if opts[:logger]
        @log ||= Logger.new(STDERR)
      end

      def receive_banner(name, version, scheme)
        if super(name, version, scheme)
          @opts[:tls] ? start_tls : succeed(self)
        end
      end

      def ssl_handshake_completed
        succeed(self)
      end

      def unbind
        return if EventMachine.stopping?

        # Give the existing broker a little time to release the port. Even if the
        # restart here fails the next time a server tries to register, a new client
        # will be created; when that fails Broker#restart will be called again.
        timeout = ENV['PRYEMBROKERTIMEOUT'].nil? || ENV['PRYEMBROKERTIMEOUT'].empty? ? RECONNECT_TO_BROKER_TIMEOUT : ENV['PRYEMBROKERTIMEOUT']
        log.info("[pry-remote-em broker-client] broker connection unbound; starting a new one in a #{timeout} seconds")
        EM::Timer.new(timeout) do
          PryRemoteEm::Broker.restart
        end
      end

    end # module::Broker
  end # module::Client
end # module::PryRemoteEm
