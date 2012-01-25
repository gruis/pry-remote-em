require 'pry-remote-em/version'
require 'eventmachine'
require 'json'

module PryRemoteEm
  DEFHOST   = 'localhost'
  DEFPORT   = 6462
  NEGOTIMER = 15
end


class Object
  def remote_pry_em(host = PryRemoteEm::DEFHOST, port = PryRemoteEm::DEFPORT, opts = {:tls => false})
    PryRemoteEm::Server.run(self, host, port, opts)
  end
end
