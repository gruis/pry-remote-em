require 'pry'
require 'pry-remote-em'
require 'fiber'

module PryRemoteEm
  module Server
    include EM::Protocols::LineText2

    class << self
      def run(obj, host = DEFHOST, port = DEFPORT)
        EM.start_server(host, port, PryRemoteEm::Server) do |pre|
          Fiber.new {
            begin
              Pry.start(obj, :input => pre, :output => pre)
            ensure
              pre.close_connection
            end
          }.resume
        end
        Kernel.puts "[pry-remote-em] listening for connections on pryem://#{DEFHOST}:#{DEFPORT}/"
      end # run(obj, host = DEFHOST, port = DEFPORT)
    end # class << self



    def post_init
      @buffer = []
      Pry.config.pager, @old_pager = false, Pry.config.pager
      Pry.config.system, @old_system = PryRemoteEm::Server::System, Pry.config.system
      # TODO negotiation TLS
      #      start_tls(:private_key_file => '/tmp/server.key', :cert_chain_file => '/tmp/server.crt', :verify_peer => false)
      # TODO authenticate user
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] received client connection from #{ip}:#{port}"
      send_data(JSON.dump({:g => PryRemoteEm::GREETING}))
    end

    def unbind
      Pry.config.pager = @old_pager
      Pry.config.system = @old_system
      Kernel.puts "[pry-remote-em] remote session terminated"
    end

    def receive_line(data)
      @buffer.push(data)
      if @waiting
        f, @waiting = @waiting, nil
        f.resume(@buffer.shift)
      end
    end

    def readline(prompt)
      send_data(JSON.dump({:p => prompt}))
      return @buffer.shift unless @buffer.empty?
      @waiting = Fiber.current
      return Fiber.yield
    end

    def print(val)
      send_data(JSON.dump({:d => val}))
    end
    alias :write :print

    def puts(data = "")
      print(data[0] == "\n" ? data : data + "\n")
    end

    def send_data(s)
      super(s + PryRemoteEm::DELIM)
    end

    System = proc do |output, cmd, _|
      output.puts("shell commands are not yet supported")
    end
  end # module::Server
end # module::PryRemoteEm
