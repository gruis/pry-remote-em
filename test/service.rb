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
EM.run{
  Foo.new(auth_hash)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :target => binding)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true)
  anon_obj.new.remote_pry_em('0.0.0.0', :auto, :tls => true)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :auth => auth_hash)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :auth => auth_anon)
  anon_obj.new.remote_pry_em('localhost', :auto, :tls => true, :auth => Authenticator.new(auth_hash))

  anon_obj.new.remote_pry_em('localhost', :auto, :auth => auth_hash)
  anon_obj.new.remote_pry_em('localhost', :auto)
}

# TODO use rspec
