require 'pry-remote-em/pk-auth'

module PryRemoteEm
  module PkAuth
    class Chain
      attr_reader :keys

      def initialize
        @keys = {}
        # TODO stop blocking the reactor
        if File.exists?(sd = File.expand_path("~/.ssh/authorized_keys"))
          IO.read(sd).each_line do |line|
            type, key, comment = line.strip.split(/\s+/, 3)
            @keys[key] = (type == 'ssh-rsa') ? Rsa.new(k) : Dsa.new(k)
          end
        end
      end # initialize

      def ok?(key, data, sig)
        raise NotImplementedError
      end # ok?(key, data, sig)
    end # class::PkAuthChain
  end # module::PkAuth
end # module::PryRemoteEm
