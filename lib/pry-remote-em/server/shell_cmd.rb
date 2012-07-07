module PryRemoteEm
  module Server
    module ShellCmd
      def initialize(pryem)
        @pryem = pryem
      end

      def receive_data(d)
        @pryem.send_shell_cmd(d.force_encoding("utf-8"))
      end

      alias :receive_stderr :receive_data

      def unbind
        @pryem.send_shell_result(get_status.exitstatus)
        @pryem.send_last_prompt
      end
    end # module::ShellCmd
  end # module::Server
end # module::PryRemoteEm
