#!/usr/bin/env ruby
require "pry-remote-em/server"

os     = ObjectSpace.each_object
expose = []
os.next.tap{ |o| expose.push(o) unless o.frozen? } while expose.length < 10
EM.run {
  expose.each {|o| o.remote_pry_em('localhost', :auto) }
}
