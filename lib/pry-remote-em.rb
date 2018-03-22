begin
  require 'openssl'
rescue LoadError
  warn "OpenSSL support is not available"
end
require 'pry-remote-em/version'
require 'pry-remote-em/proto'
require 'eventmachine'
require 'socket'
require 'fiber'
require 'uri'

module PryRemoteEm
  DEFHOST         = '127.0.0.1'
  DEFPORT         = 6463
  DEF_BROKERPORT  = 6462
  DEF_BROKERHOST  = '127.0.0.1'
  NEGOTIMER       = 15
end


class Object
  def remote_pry_em(host = PryRemoteEm::DEFHOST, port = PryRemoteEm::DEFPORT, opts = {:tls => false}, &blk)
    opts = {:target => self}.merge(opts)
    PryRemoteEm::Server.run(opts[:target], host, port, opts, &blk)
  end
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
