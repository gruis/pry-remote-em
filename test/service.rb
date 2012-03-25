#!/usr/bin/env ruby
require 'pry-remote-em/server'


auth_hash = {'caleb' => 'crane', 'john' => 'lowski'}
auth_anon = lambda do |user, pass|
  return true if 'anonymous' == user
  auth_hash[user] && auth_hash[user] == pass
end
class Authenticator
  def initialize(db)
    @db = db
  end
  def call(user, pass)
    @db[user] && @db[user] == pass
  end
end


class Foo
  def initialize(auth)
    binding.remote_pry_em('127.0.0.1', 1337, auth: auth)
  end
end

anon_obj = Class.new do
  def keys
    [:encoding, :weather]
  end
  def encoding
    __ENCODING__
  end
  def weather
    :cloudy
  end
end

log         = ::Logger.new(STDERR)
auth_logger = lambda do |pry|
  pry.auth_attempt do |user, ip|
    log.info("got an authentication attempt for #{user} from #{ip}")
  end
  pry.auth_fail do |user, ip|
    log.fatal("failed authentication attempt for #{user} from #{ip}")
  end
  pry.auth_ok do |user, ip|
    log.info("successful authentication for #{user} from #{ip}")
  end
end


EM.run{
  binding.remote_pry_em
  Foo.new(auth_hash)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :target => binding)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :allow_shell_cmds => true)
  anon_obj.new.remote_pry_em('0.0.0.0', :auto, :tls => true)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :allow_shell_cmds => true, :auth => auth_hash) do |pry|
    auth_logger.call(pry)
  end
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :auth => auth_anon) do |pry|
    auth_logger.call(pry)
  end
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :auth => Authenticator.new(auth_hash)) do |pry|
    auth_logger.call(pry)
  end
  anon_obj.new.remote_pry_em('localhost', :auto, :auth => auth_hash) do |pry|
    auth_logger.call(pry)
  end
  anon_obj.new.remote_pry_em('localhost', :auto)
}

# TODO use rspec
