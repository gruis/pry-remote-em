module PryRemoteEm
  class IO
    attr_reader :fileno

    def initialize(io)
      @io       = io.to_io
      @fileno   = @io.fileno
      @clients  = []
    end

    def register(client)
      return if @clients.include?(client)
      @clients << client
    end

    def unregister(client)
      @clients.delete(client)
    end

    def puts(*args)
      # clients waiting for responses are not the client responsible
      # for this #puts call; not true in a Threaded environment
      @clients && @clients.each { |c|
        !c.waiting? && c.puts(*args)
      }
      @io.puts(*args)
    end

    def print(*args)
      # clients waiting for responses are not the client responsible
      # for this #puts call; not true in a Threaded environment
      @clients && @clients.each { |c|
        !c.waiting? && c.print(*args)
      }
      @io.print(*args)
    end
    alias :write :print

    def gets(*args)
      f     = Fiber.current
      given = false
      @clients.each do |c|
        # clients waiting for responses are not the client responsible
        # for this #puts call; not true in a Threaded environment
        next if c.waiting?
        Fiber.new {
          got = c.gets(*args)
          if !given && f.alive?
            given = true
            f.resume(got)
          end
        }.resume
      end
      return Fiber.yield
    end

    def tty?
      true
    end

    def flush
      true
    end

    def eof?
      false
    end

    def to_io
      self
    end

    def method_missing(meth, *args, &blk)
      STDERR.puts "call to io (#{fileno}) #{meth.inspect} not overriden by PryRemoteEm::IO"
      block_given? ? send(meth, *args, &blk) : send(meth, *args)
    end

  end
end
