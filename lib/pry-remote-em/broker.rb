require 'pry-remote-em'

module PryRemoteEm
  module Broker
    class << self
      attr_reader :listening, :host, :port
      alias :listening? :listening

      def run(host = DEF_BROKERHOST, port = DEF_BROKERPORT, opts = {:tls => false})
       raise "root permission required for port below 1024 (#{port})" if port < 1024 && Process.euid != 0
       @host = host
       @port = port
       @opts = opts
       begin
         EM.start_server(host, port, PryRemoteEm::Broker, opts) do |broker|
         end
         log.info("[pry-remote-em broker] listening on #{host}:#{port}")
         @listening = true
       rescue => e
         # EM 1.0.0.beta4's message tells us the port is in use; 0.12.10 just says, 'no acceptor'
         if (e.message.include?('port is in use') || e.message.include?('no acceptor'))
           # [pry-remote-em broker] a broker is already listening on #{host}:#{port}
         else
           raise e
         end
       end
      end

      def opts
        @opts ||= {}
      end

      def log
        return opts[:logger] if opts[:logger]
        @log ||= Logger.new(STDERR)
      end

      def servers
        @servers ||= {}
      end

      def register(url, name = 'unknown')
        if listening?
          servers[url] = name
          log.info("[pry-remote-em broker] registered #{url} - #{name.inspect}")
        else
          client.send_register_server(url, name)
        end
        name
      end

      def unregister(server)
        if listening?
          servers.delete(url)
          log.info("[pry-remote-em broker] unregistered #{server}")
        else
          client.send_unregister_server(server)
        end
        server
      end

    private

      def client
        @client ||= EM.connect( host, port, (Module.new {include(PryRemoteEm::Proto)}) )
      end
    end # class << self

    def receive_register_server(url, name)
      Broker.register(url, name)
    end

    def receive_unregister_server(url)
      Broker.unregister(url, name)
    end

    def receive_heartbeat(url)

    end

  end # module::Broker
end # module::PryRemoteEm
