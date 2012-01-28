require 'openssl'

module PryRemoteEm
  module PkAuth
    class Dsa
      def initialize(k)
        @key = OpenSSL::Pkey::DSA.new(k)
      end
      def verify(sig, data)
        raise NotImplementedError
      end
      def sign(data)
        raise NotImplementedError
      end
    end # class::Dsa
  end # module::PkAuth
end # module::PryRemoteEm
