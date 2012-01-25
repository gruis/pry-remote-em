require 'pry-remote-em/version'
require 'eventmachine'
require 'json'

module PryRemoteEm
  DEFHOST   = 'localhost'
  DEFPORT   = 6462
  DELIM     = ']]>]]><[[<[['
  NEGOTIMER = 15
  GREETING  = "PryRemoteEm #{VERSION}"
end


class Object
  def remote_pry_em(host = PryRemoteEm::DEFHOST, port = PryRemoteEm::DEFPORT)
    PryRemoteEm::Server.run(self, host, port)
  end
end
