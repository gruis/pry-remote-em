require 'termios'
module PryRemoteEm
  module Client
    module Keyboard

      def initialize(c)
        @con            = c
        # TODO check actual current values to determine if it's enabled or not
        @buff_enabled   = true
        # On EM < 1.0.0.beta.4 the keyboard handler and Termios don't work well together
        # readline will complain that STDIN isn't a tty after Termios manipulation, so
        # just don't let it happen
        @manip_buff     = Gem.loaded_specs['eventmachine'].version >= Gem::Version.new('1.0.0.beta.4')
        bufferio(false)
        # TODO retain the old SIGINT handler and reset it later
        trap :SIGINT do
          @con.send_data({ssc: true})
        end
      end

      def receive_data(d)
        @con.send_data({sd: d})
      end

      def unbind
        bufferio(true)
        trap :SIGINT do
          Process.exit
        end
      end

      # Makes stdin buffered or unbuffered.
      # In unbuffered mode read and select will not wait for "\n"; also will not echo characters.
      # This probably does not work on Windows.
      # On EventMachine < 1.0.0.beta.4 this method doesn't do anything
      def bufferio(enable)
        return if !@manip_buff || (enable && @buff_enabled) || (!enable && !@buff_enabled)
        attr = Termios.getattr($stdin)
        enable ? (attr.c_lflag |= Termios::ICANON | Termios::ECHO) : (attr.c_lflag &= ~(Termios::ICANON|Termios::ECHO))
        Termios.setattr($stdin, Termios::TCSANOW, attr)
        @buff_enabled = enable
      end
    end # module::Keyboard
  end # module::Client
end # module PryRemoteEm

