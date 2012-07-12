require 'pry-remote-em'
require 'pry-remote-em/client/broker'

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
         log.info("[pry-remote-em broker] listening on #{opts[:tls] ? 'pryems' : 'pryem'}://#{host}:#{port}")
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
        client {|c| c.send_register_server(url, name) }
      end

      def unregister(server)
        client {|c| c.send_unregister_server(server) }
      end

    private

      def client(&blk)
        raise ArgumentError.new("A block is required") unless block_given?
        if @client
          yield @client
          return
        end

        if @waiting
          @waiting << blk
        else
          @waiting = []
          EM.connect(host, port, Client::Broker, @opts) do |client|
            client.errback { |e| raise(e || "broker client error") }
            client.callback do
              @client = client
              while (w = @waiting.shift)
                w.call(client)
              end
            end
          end
        end
      end
    end # class << self

    include Proto

    def log
      Broker.log
    end

    def initialize(opts = {:tls => false}, &blk)
      @opts = opts
    end

    def post_init
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      log.info("[pry-remote-em broker] received client connection from #{ip}:#{port}")
      send_banner("PryRemoteEm #{VERSION} #{@opts[:tls] ? 'pryems' : 'pryem'}")
      @opts[:tls] ? start_tls : send_server_list(Broker.servers)
    end

    def start_tls
      log.debug("[pry-remote-em broker] starting TLS (#{peer_ip}:#{peer_port})")
      send_start_tls
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def peer_ip
      return @peer_ip if @peer_ip
      return "" if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_ip
    end

    def peer_port
      return @peer_port if @peer_port
      return "" if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_port
    end

    def ssl_handshake_completed
      log.info("[pry-remote-em broker] TLS connection established (#{peer_ip}:#{peer_port})")
      send_server_list(Broker.servers)
    end

    def receive_server_list
      send_server_list(Broker.servers)
    end

    def receive_register_server(url, name)
      url      = URI.parse(url)
      url.host = peer_ip if url.host == "0.0.0.0"
      Broker.servers[url] = name
      log.info("[pry-remote-em broker] registered #{url} - #{name.inspect}")
      name
    end

    def receive_unregister_server(url)
      Broker.servers.delete(url)
    end

    def receive_heartbeat(url)

    end

  end # module::Broker
end # module::PryRemoteEm
