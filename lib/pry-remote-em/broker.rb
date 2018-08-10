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

      def run(host = nil, port = nil, opts = {})
        host ||= ENV['PRYEMBROKER'].nil? || ENV['PRYEMBROKER'].empty? ? DEFAULT_BROKER_HOST : ENV['PRYEMBROKER']
        port ||= ENV['PRYEMBROKERPORT'].nil? || ENV['PRYEMBROKERPORT'].empty? ? DEFAULT_BROKER_PORT : ENV['PRYEMBROKERPORT']
        port = port.to_i if port.kind_of?(String)
        raise "root permission required for port below 1024 (#{port})" if port < 1024 && Process.euid != 0
        @host = host
        @port = port
        opts = opts.dup
        # Brokers cannot use SSL directly. If they do then when a proxy request to an SSL server is received
        # the client and server will not be able to negotiate a SSL session. The proxied traffic can be SSL
        # encrypted, but the SSL session will be between the client and the server.
        opts[:tls] = false
        @opts = opts
        start_server(host, port, opts) unless @listening || ENV['PRYEMREMOTEBROKER'] || @opts[:remote_broker]
        client { |c| yield self } if block_given?
      end

      def restart
        log.info("[pry-remote-em broker] restarting on pryem://#{host}:#{port}")
        @waiting   = nil
        @client    = nil
        run(@host, @port, @opts) do
          PryRemoteEm.servers.each do |id, description|
            next unless EM.get_sockname(description[:server])
            register(
              id: description[:id],
              urls: description[:urls],
              name: description[:name],
              details: description[:details],
              metrics: PryRemoteEm::Metrics.list
            )
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

      def register(description)
        client { |c| c.send_register_server(description[:id], description[:urls], description[:name], description[:details], description[:metrics]) }
      end

      def unregister(id)
        client { |c| c.send_unregister_server(id) }
      end

      def register_server(id, description)
        servers[id] = description
        watch_heartbeats(id)
        log.info("[pry-remote-em broker] registered #{id} #{description.inspect}")
      end

      def update_server(server, description)
        server.update(urls: description[:urls], name: description[:name])
        server[:details].update(description[:details])
        server[:metrics].update(description[:metrics])
      end

      def unregister_server(id)
        server = servers.delete(id) or return
        log.warn("[pry-remote-em broker] unregister #{id} #{server.inspect}")
        timer = timers.delete(id)
        timer.cancel if timer
        hbeats.delete(id)
      end

      def watch_heartbeats(id)
        interval = ENV['PRYEMHBCHECK'].nil? || ENV['PRYEMHBCHECK'].empty? ? HEARTBEAT_CHECK_INTERVAL : ENV['PRYEMHBCHECK']
        timers[id] ||= EM::PeriodicTimer.new(interval) do
          if !hbeats[id] || (Time.new - hbeats[id]) > 20
            unregister_server(id)
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

      def start_server(host, port, opts)
        EM.start_server(host, port, PryRemoteEm::Broker, opts)
        log.info("[pry-remote-em broker] listening on #{opts[:tls] ? 'pryems' : 'pryem'}://#{host}:#{port}")
        @listening = true
      rescue => error
        if error.message.include?('port is in use')
          if opts[:raise_if_port_in_use]
            raise
          else
            # A broker is already listening on this port, we can do nothing
          end
        else
          raise
        end
      end

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

    def receive_server_reload_list
      send_server_list(Broker.servers)
    end

    def receive_register_server(id, urls, name, details, metrics)
      @ids.push(id)
      description = { urls: urls, name: name, details: details, metrics: metrics }
      Broker.hbeats[id] = Time.new
      server = Broker.servers[id]
      if server
        Broker.update_server(server, description)
      else
        Broker.register_server(id, description)
      end
    end

    def receive_unregister_server(id)
      server = Broker.servers[id]
      Broker.unregister_server(id) if server
    end

    def receive_proxy_connection(url)
      log.info("[pry-remote-em broker] proxying to #{url}")
      url = URI.parse(url)
      EM.connect(url.host, url.port, Client::Proxy, self)
    end

    def initialize(opts = {}, &blk)
      @opts = opts
      @ids = []
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

    def unbind
      @ids.each do |id|
        Broker.unregister_server(id)
      end
    end
  end # module::Broker
end # module::PryRemoteEm
