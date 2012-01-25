require 'readline'
require 'pry-remote-em'

module PryRemoteEm
  module Client
    include EM::Deferrable

    def post_init
      @buffer  = ""
      return fail("connection was not established") unless get_peername
      port, ip = Socket.unpack_sockaddr_in(get_peername)
      Kernel.puts "[pry-remote-em] client connected to #{ip}:#{port}"
      @nego_timer = EM::Timer.new(PryRemoteEm::NEGOTIMER) do
        fail("[pry-remote-em] server didn't finish negotiation within #{PryRemoteEm::NEGOTIMER} seconds; terminating")
      end
    end

    def receive_data(d)
      return unless d && d.length > 0
      if six = d.index(PryRemoteEm::DELIM)
        @buffer << d[0...six]
        j = JSON.load(@buffer)
        @buffer.clear
        receive_json(j)
        receive_data(d[(six + PryRemoteEm::DELIM.length)..-1])
      else
        @buffer << d
      end
    end

    def receive_json(j)
      if j['p']
        send_data(Readline.readline(j['p'], true) + "\n") if @negotiated && !@unbound

      elsif j['d']
        print j['d']

      elsif j['g']
        Kernel.puts "[pry-remote-em] remote is #{j['g']}"
        # TODO parse version and compare against a Gem style matcher
        if j['g'] == PryRemoteEm::GREETING
          @nego_timer.cancel
          @negotiated = true
        else
          fail("incompatible version")
        end

      else
        warn "received unexpected data: #{j}"
      end
    end

    def unbind
      @unbound = true
      Kernel.puts "[pry-remote-em] session terminated"
      error? ? fail : succeed
    end
  end # module::Client
end # module::PryRemoteEm
