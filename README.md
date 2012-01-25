# What is it?

A way to start Pry remotely in EventMachine and to connect to it. This provides access to the state of the running program from anywhere.

It's based off of [Mon-Ouie's](https://github.com/Mon-Ouie) [pry-remote](https://github.com/Mon-Ouie/pry-remote) for DRb.

# Compatibility

  MRI 1.9 or any other VM with support for Fibers is required.


# Installation

```bash
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

     [pry-remote-em] listening for connections on pryem://localhost:6462/

You can then connect to the pry session using ``pry-remote-em``:

    $ pry-remote-em
    [pry-remote-em] client connected to pryem://127.0.0.1:6462/
    [pry-remote-em] remote is PryRemoteEm 0.1.0
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
    [pry-remote-em] client connected to pryem://127.0.0.1:6462/
    [pry-remote-em] remote is PryRemoteEm 0.1.0
    [1] pry(#<Foo>)> x
    => 12

    [2] pry(#<Foo>)> exit
    [pry-remote-em] session terminated

# Features

## TLS Encryption
  
  When creating a server pass the :tls => true option to enable TLS. If
you pass a Hash, e.g. ``:tls => {:private_key_file => '/tmp/server.key'}`` it will be used to configure the internal TLS handler. 
  See [EventMachine::Connection#start_tls](http://eventmachine.rubyforge.org/EventMachine/Connection.html#M000296) for the available options.

 To start the command line client in TLS mode pass it a pryems URL instead of a pryem URL.

```bash
  $ bin/pry-remote-em pryems:///
  [pry-remote-em] client connected to pryem://127.0.0.1:6462/
  [pry-remote-em] remote is PryRemoteEm 0.1.0 pryems
  [pry-remote-em] negotiating TLS
  [pry-remote-em] TLS connection established
  [1] pry(#<Hash>)> 
```

# Missing Features

  - User authentication
  - Tab completion
