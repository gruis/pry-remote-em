# What is it?

A way to start Pry remotely and to connect to it in EventMachine. This allows to
access the state of the running program from anywhere.

It's based off of [Mon-Ouie's](https://github.com/Mon-Ouie) [pry-remote](https://github.com/Mon-Ouie/pry-remote) for DRb.

# Compatibility

  Ruby 1.9 or any other VM with support for Fibers is required.


# Installation

```shell
gem install pry-remote-em
```

# Usage

```ruby
require 'pry-remote-em/server'

class Foo
  def initialize(x, y)
    binding.remote_pry_em
  end
end

EM.run { Foo.new 10, 20 } 
```

Running it will print out a message telling you Pry is waiting for a
program to connect itself to it:

     [pry-remote-em] listening for connections on localhost:6462

You can then connect yourself using ``pry-remote-em``:

    $ pry-remote-em
    [pry-remote-em] client connected to 127.0.0.1:6462
    [pry-remote-em] remote is PryRemoteEm 0.0.0
    [1] pry(#<Foo>)> stat
    Method Information:
    --
    Name: initialize
    Owner: Foo
    Visibility: private
    Type: Bound
    Arity: 2
    Method Signature: initialize(x, y)
    Source Location: (irb):2

    [2] pry(#<Foo>)> self
    => #<Foo:0x007fe66a426fa0>

    [3] pry(#<Foo>)> ls
    locals: _  _dir_  _ex_  _file_  _in_  _out_  _pry_  x  y
    [4] pry(#<Foo>)> x
    => 10

    [5] pry(#<Foo>)> x = 12
    => 12

    [6] pry(#<Foo>)> x
    => 12

    [7] pry(#<Foo>)> exit
    [pry-remote-em] session terminated

    $ pry-remote-em
    [pry-remote-em] client connected to 127.0.0.1:6462
    [pry-remote-em] remote is PryRemoteEm 0.0.0
    [1] pry(#<Foo>)> x
    => 12

    [2] pry(#<Foo>)> exit
    [pry-remote-em] session terminated

# Missing Features

  - User authentication
  - TLS encryption
  - Tab completion
