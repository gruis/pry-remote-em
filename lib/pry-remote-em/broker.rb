require 'logger'
require 'socket'
require 'pry-remote-em'
require 'pry-remote-em/client/broker'
require 'pry-remote-em/client/proxy'

module PryRemoteEm
  module Broker
    class << self
      attr_reader :listening, :host, :port
      alias :listening? :listening

      def run(host = nil, port = nil, opts = { tls: false })
        host ||= ENV['PRYEMBROKER'].nil? || ENV['PRYEMBROKER'].empty? ? DEF_BROKERHOST : ENV['PRYEMBROKER']
        port ||= ENV['PRYEMBROKERPORT'].nil? || ENV['PRYEMBROKERPORT'].empty? ? DEF_BROKERPORT : ENV['PRYEMBROKERPORT']
        port = port.to_i if port.kind_of?(String)
        raise "root permission required for port below 1024 (#{port})" if port < 1024 && Process.euid != 0
        @host      = host
        @port      = port
        # Brokers cannot use SSL directly. If they do then when a proxy request to an SSL server is received
        # the client and server will not be able to negotiate a SSL session. The proxied traffic can be SSL
        # encrypted, but the SSL session will be between the client and the server.
        opts       = opts.dup
        opts[:tls] = false
        @opts      = opts
        unless ENV['PRYEMREMOTEBROKER'] || @opts[:remote_broker]
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
        client { |c| yield self } if block_given?
      end

      def restart
        log.info("[pry-remote-em broker] restarting on pryem://#{host}:#{port}")
        @waiting   = nil
        @client    = nil
        run(@host, @port, @opts) do
          PryRemoteEm.servers.each do |url, (sig, name)|
            next unless EM.get_sockname(sig)
            register(url, name)
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
        expand_url(url).each do |u|
          client { |c| c.send_register_server(u, name) }
        end
      end

      def unregister(url)
        expand_url(url).each do |u|
          client { |c| c.send_unregister_server(u) }
        end
      end

      def expand_url(url)
        return Array(url) if (u = URI.parse(url)).host != '0.0.0.0'
        Socket.ip_address_list.select { |a| a.ipv4? }
         .map(&:ip_address).map{|i| u.clone.tap{|mu| mu.host = i } }
      end

      def watch_heartbeats(url)
        return if timers[url]
        timers[url] = EM::PeriodicTimer.new(20) do
          if !hbeats[url] || (Time.new - hbeats[url]) > 20
            servers.delete(url)
            timers[url].cancel
            timers.delete(url)
          end
        end
      end

      def timers
        @timers ||= {}
      end

      def hbeats
        @hbeats ||= {}
      end

      def connected?
        @connected
      end

    private

      def client(&blk)
        raise ArgumentError.new('A block is required') unless block_given?
        if @client
          yield @client
          return
        end

        if @waiting
          @waiting << blk
        else
          @waiting = [blk]
          EM.connect(host, port, Client::Broker, @opts) do |client|
            client.errback { |e| raise(e || 'broker client error') }
            client.callback do
              @client    = client
              while (w = @waiting.shift)
                w.call(client)
              end
            end
          end
        end
      end
    end # class << self

    include Proto

    def receive_server_list
      send_server_list(Broker.servers)
    end

    def receive_register_server(url, name)
      url = URI.parse(url)
      url.hostname = peer_ip if ['0.0.0.0', 'localhost', '127.0.0.1', '::1'].include?(url.hostname)
      log.info("[pry-remote-em broker] registered #{url} - #{name.inspect}") unless Broker.servers[url] == name
      Broker.servers[url] = name
      Broker.hbeats[url]  = Time.new
      Broker.watch_heartbeats(url)
      name
    end

    def receive_unregister_server(url)
      url = URI.parse(url)
      url.hostname = peer_ip if ['0.0.0.0', 'localhost', '127.0.0.1', '::1'].include?(url.hostname)
      log.warn("[pry-remote-em broker] unregister #{url}")
      Broker.servers.delete(url)
    end

    def receive_proxy_connection(url)
      log.info("[pry-remote-em broker] proxying to #{url}")
      url = URI.parse(url)
      EM.connect(url.host, url.port, Client::Proxy, self)
    end

    def initialize(opts = { tls: false }, &blk)
      @opts   = opts
    end

    def log
      Broker.log
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
      return '' if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_ip = '127.0.0.1' if @peer_ip == '::1' # Little hack to avoid segmentation fault in EventMachine 1.2.0.1 while connecting to PryRemoteEm Server from localhost with IPv6 address
      @peer_ip
    end

    def peer_port
      return @peer_port if @peer_port
      return '' if get_peername.nil?
      peer_ip # Fills peer_port too
      @peer_port
    end

    def ssl_handshake_completed
      log.info("[pry-remote-em broker] TLS connection established (#{peer_ip}:#{peer_port})")
      send_server_list(Broker.servers)
    end

  end # module::Broker
end # module::PryRemoteEm
