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


obj = {:encoding => __ENCODING__, :weather => :cloudy}
EM.run{
  Foo.new(auth_hash)
  obj.remote_pry_em('localhost', :auto, :tls => true, :target => binding)
  obj.remote_pry_em('localhost', :auto, :tls => true)
  obj.remote_pry_em('0.0.0.0', :auto, :tls => true)
  obj.remote_pry_em('localhost', :auto, :tls => true, :auth => auth_hash)
  obj.remote_pry_em('localhost', :auto, :tls => true, :auth => auth_anon)
  obj.remote_pry_em('localhost', :auto, :tls => true, :auth => Authenticator.new(auth_hash))

  obj.remote_pry_em('localhost', :auto, :auth => auth_hash)
  obj.remote_pry_em('localhost', :auto)
}

# TODO use rspec
