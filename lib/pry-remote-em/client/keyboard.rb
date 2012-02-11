require "termios"
module PryRemoteEm
  module Client
    module Keyboard

      def initialize(c)
        @con = c
        bufferio(false)
        # TODO retain the old SIGINT handler and reset it later
        trap :SIGINT do
          @con.send_data({:ssc => true})
        end
      end

      def receive_data(d)
        @con.send_data({:sd => d})
      end

      def unbind
        bufferio(true)
        trap :SIGINT do
          Process.exit
        end
      end

      # Makes stdin buffered or unbuffered.
      # In unbuffered mode read and select will not wait for "\n"; also will not echo characters.
      # This probably does not work on Windows
      def bufferio( enable, io = $stdin )
        attr = Termios::getattr( io )
        enable ? (attr.c_lflag |= Termios::ICANON | Termios::ECHO) : (attr.c_lflag &= ~(Termios::ICANON|Termios::ECHO))
        Termios::setattr( $stdin, Termios::TCSANOW, attr )
      end
    end # module::Keyboard
  end # module::Client
end # module PryRemoteEm

