#!/usr/bin/env ruby
require 'pry-remote-em/server'
require 'highline'

class Std
  def ping
    "pong"
  end

  def say(msg = "pry rocks!")
    puts msg
  end

  def ask
    "42" == HighLine.new.ask("What is the Ultimate Answer to the Ultimate Question of Life, The Universe, and Everything? ")
  end
end

EM.run { Std.new.remote_pry_em('0.0.0.0', :auto) }
