require 'openssl'

module PryRemoteEm
  module PkAuth
    class Rsa
      def initialize(k)
        @key = OpenSSL::Pkey::RSA.new(k)
      end
      def verify(sig, data)
        @key.verify(OpenSSL::Digest::SHA1.new, sig, data)
      end
      def sign(data)
        @key.sign(OpenSSL::Digest::SHA1.new, data)
      end
    end # class::Rsa
  end # module::PkAuth
end # module::PryRemoteEm
