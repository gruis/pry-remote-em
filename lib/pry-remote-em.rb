begin
  require 'openssl'
rescue LoadError
  warn 'OpenSSL support is not available'
end
require 'pry-remote-em/version'
require 'pry-remote-em/proto'
require 'eventmachine'
require 'socket'
require 'fiber'
require 'uri'

module PryRemoteEm
  DEFAULT_SERVER_HOST = '127.0.0.1'
  DEFAULT_SERVER_PORT = 6463
  DEFAULT_BROKER_HOST = '127.0.0.1'
  DEFAULT_BROKER_PORT = 6462

  NEGOTIATION_TIMEOUT         = 15
  HEARTBEAT_SEND_INTERVAL     = 15
  HEARTBEAT_CHECK_INTERVAL    = 20
  RECONNECT_TO_BROKER_TIMEOUT = 3

  MAXIMUM_ERRORS_IN_SANDBOX = 100
end


class Object
  def remote_pry_em(host = nil, port = nil, options = {}, &block)
    host, options = nil, host if host.kind_of?(Hash) # Support for options hash as first argument instead of third

    options = { target: self, host: host, port: port }.merge(options)
    PryRemoteEm::Server.run(options, &block)
  end

  alias pry_remote_em remote_pry_em # source of common confusing
end


unless defined?(EventMachine.popen3)
  module EventMachine
    # @see http://eventmachine.rubyforge.org/EventMachine.html#M000491
    # @see https://gist.github.com/535644/4d5b645b96764e07ccb53539529bea9270741e1a
    def self.popen3(cmd, handler=nil, *args)
      klass = klass_from_handler(Connection, handler, *args)
      w     = Shellwords::shellwords(cmd)
      w.unshift(w.first) if w.first

      new_stderr = $stderr.dup
      rd, wr     = IO::pipe

      $stderr.reopen wr
      s = invoke_popen(w)
      $stderr.reopen new_stderr

      klass.new(s, *args).tap do |c|
        EM.attach(rd, Popen3StderrHandler, c)
        @conns[s] = c
        yield(c) if block_given?
      end
    end

    class Popen3StderrHandler < EventMachine::Connection
      def initialize(connection)
        @connection = connection
      end

      def receive_data(data)
        @connection.receive_stderr(data)
      end
    end  # class::Popen3StderrHandler
  end # module::EventMachine
end # defined?(EventMachine.popen3)
