require "pry-remote-em/client/generic"
module PryRemoteEm
  module Client
    module Proxy

      def initialize(client, opts = {})
        @opts   = opts
        @client = client
      end

      def connection_completed
        if get_peername
          port, ip = Socket.unpack_sockaddr_in(get_peername)
          log.info("[pry-remote-em] proxy connected to pryem://#{ip}:#{port}/")
        else
          log.info("[pry-remote-em] proxy connected")
        end
        @client.proxy_incoming_to(self)
        proxy_incoming_to(@client)
      end

      def log
        return @opts[:logger] if @opts[:logger]
        @log ||= Logger.new(STDERR)
      end

      def unbind
        @client && @client.close_connection(true)
      end
    end # module::Proxy
  end # module::Client
end # module::PryRemoteEm
