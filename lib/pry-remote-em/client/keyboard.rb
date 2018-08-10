require 'termios' unless RUBY_PLATFORM =~ /java/

module PryRemoteEm
  module Client
    module Keyboard

      def initialize(c)
        @con            = c
        # TODO check actual current values to determine if it's enabled or not
        @buff_enabled   = true

        bufferio(false)

        @old_trap = Signal.trap(:INT) do
          @con.send_shell_sig(:int)
        end
      end

      def receive_data(d)
        print d.chr
        @con.send_shell_data(d)
      end

      def unbind
        bufferio(true)

        Signal.trap(:INT, @old_trap)
      end

      # Makes stdin buffered or unbuffered.
      # In unbuffered mode read and select will not wait for "\n"; also will not echo characters.
      # This probably does not work on Windows.
      def bufferio(enable)
        return if !defined?(Termios) || enable && @buff_enabled || !enable && !@buff_enabled
        attr = Termios.getattr($stdin)
        enable ? (attr.c_lflag |= Termios::ICANON | Termios::ECHO) : (attr.c_lflag &= ~(Termios::ICANON|Termios::ECHO))
        Termios.setattr($stdin, Termios::TCSANOW, attr)
        @buff_enabled = enable
      end
    end # module::Keyboard
  end # module::Client
end # module PryRemoteEm
