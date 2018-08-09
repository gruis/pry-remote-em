[PryRemoteEm](https://rubygems.org/gems/pry-remote-em) enables you to
start instances of Pry in a running
[EventMachine](http://rubyeventmachine.com/) program and connect to
those Pry instances over a network or the Internet. Once connected you
can interact with the internal state of the program.

It's based off of [Mon-Ouie's](https://github.com/Mon-Ouie) [pry-remote](https://github.com/Mon-Ouie/pry-remote) for DRb.

It adds user authentication and SSL support along with tab-completion
and paging. It's compatble with MRI 1.9, or any other VM with support
for Fibers and EventMachine.


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

     [pry-remote-em] listening for connections on pryem://127.0.0.1:6462/

You can then connect to the pry session using ``pry-remote-em``:

    $ pry-remote-em pryem://127.0.0.1:6462/
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

    $ pry-remote-em pryem://127.0.0.1:6462/
    [pry-remote-em] client connected to pryem://127.0.0.1:6462/
    [pry-remote-em] remote is PryRemoteEm 0.1.0
    [1] pry(#<Foo>)> x
    => 12

    [2] pry(#<Foo>)> exit
    [pry-remote-em] session terminated

# Features

## Multiple Servers

It's easy to run more than one PryRemoteEm service on a single machine,
or even in the same process. When you start the service via
*#remote_pry_em*, just specify *:auto* as the port to use. The service
will automatically take the next free port from 6462.

```ruby
require 'pry-remote-em/server'

os     = ObjectSpace.each_object
expose = []
while expose.length < 5
  o = os.next
  expose.push(o) unless o.frozen?
end

EM.run do
  expose.each {|o| o.remote_pry_em('localhost', :auto) }
end
```

    $ ruby test/auto-demo.rb
    [pry-remote-em] listening for connections on pryem://localhost:6462/
    [pry-remote-em] listening for connections on pryem://localhost:6463/
    [pry-remote-em] listening for connections on pryem://localhost:6464/
    [pry-remote-em] listening for connections on pryem://localhost:6465/
    [pry-remote-em] listening for connections on pryem://localhost:6466/

```shell

$ pry-remote-em pryem://127.0.0.1:6462/
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[1] pry("pretty_print")>

$ pry-remote-em  pryem://127.0.0.1:6463/
[pry-remote-em] client connected to pryem://127.0.0.1:6463/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[1] pry("pack")>

$ pry-remote-em  pryem://127.0.0.1:6464/
[pry-remote-em] client connected to pryem://127.0.0.1:6464/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[1] pry("to_json")>

$ pry-remote-em  pryem://127.0.0.1:6465/
[pry-remote-em] client connected to pryem://127.0.0.1:6465/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[1] pry("to_json")>

$ pry-remote-em  pryem://127.0.0.1:6466/
[pry-remote-em] client connected to pryem://127.0.0.1:6466/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[1] pry(#<RubyVM::InstructionSequence>)>
```

## Server Broker

When more than one server is running on a given host and each server is
started with :auto it can be time consuming to manually figure out which
port each server is running on. The Broker which listens on port 6462
keeps track of which server is running on which port.

By default the pry-remote-em cli utility will connect to the broker and
retrieve a list of known servers. You can then select one to connect to
by its id, name or url. You can also choose to proxy your connection
through the broker to the selected server.

```shell

$ bin/pry-remote-em
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 0.7.0 pryem
-----------------------------------------------------------------------------
| id  |  name                              |  url                           |
-----------------------------------------------------------------------------
|  1  |  #<#<Class:0x007f924b9bbee8>>      |  pryem://127.0.0.1:6462/       |
|  2  |  #<Foo>                            |  pryem://127.0.0.1:1337/       |
|  3  |  #<#<Class:0x007f924b9bbee8>>      |  pryems://127.0.0.1:6463/      |
|  4  |  #<#<Class:0x007f924b9bbee8>>      |  pryems://127.0.0.1:6464/      |
|  5  |  #<#<Class:0x007f924b9bbee8>>      |  pryems://127.0.0.1:6465/      |
|  6  |  #<#<Class:0x007f924b9bbee8>>      |  pryems://127.0.0.1:6466/      |
|  7  |  #<#<Class:0x007f924b9bbee8>>      |  pryems://127.0.0.1:6467/      |
|  8  |  #<#<Class:0x007f924b9bbee8>>      |  pryem://127.0.0.1:6468/       |
|  9  |  #<#<Class:0x007f924b9bbee8>>      |  pryem://127.0.0.1:6469/       |
-----------------------------------------------------------------------------
(q) to quit; (r) to refresh (p) to proxy
connect to: 3
[pry-remote-em] client connected to pryem://127.0.0.1:6463/
[pry-remote-em] remote is PryRemoteEm 0.7.0 pryems
[pry-remote-em] negotiating TLS
[pry-remote-em] TLS connection established
[1] pry(#<#<Class:0x007f924b9bbee8>>)>
```

By default the Broker will listen on 127.0.0.1:6462. To change the ip
address that the Broker binds to specify it in a PRYEMBROKER environment
variable, or in :broker_host option passed to #remote_pry_em.

```shell

$ PRYEMBROKER=0.0.0.0 be ./test/service.rb
I, [2012-07-13T21:10:00.936993 #88528]  INFO -- : [pry-remote-em] listening for connections on pryem://0.0.0.0:6462/
I, [2012-07-13T21:10:00.937132 #88528]  INFO -- : [pry-remote-em broker] listening on pryem://0.0.0.0:6462
I, [2012-07-13T21:10:00.937264 #88528]  INFO -- : [pry-remote-em] listening for connections on pryem://0.0.0.0:1337/
I, [2012-07-13T21:10:00.937533 #88528]  INFO -- : [pry-remote-em] listening for connections on pryems://0.0.0.0:6463/
I, [2012-07-13T21:10:00.937804 #88528]  INFO -- : [pry-remote-em] listening for connections on pryems://0.0.0.0:6464/
I, [2012-07-13T21:10:00.938126 #88528]  INFO -- : [pry-remote-em] listening for connections on pryems://0.0.0.0:6465/
I, [2012-07-13T21:10:00.938471 #88528]  INFO -- : [pry-remote-em] listening for connections on pryems://0.0.0.0:6466/
I, [2012-07-13T21:10:00.938835 #88528]  INFO -- : [pry-remote-em] listening for connections on pryems://0.0.0.0:6467/
I, [2012-07-13T21:10:00.939230 #88528]  INFO -- : [pry-remote-em] listening for connections on pryem://0.0.0.0:6468/
I, [2012-07-13T21:10:00.939640 #88528]  INFO -- : [pry-remote-em] listening for connections on pryem://0.0.0.0:6469/
I, [2012-07-13T21:10:01.031576 #88528]  INFO -- : [pry-remote-em broker] received client connection from 127.0.0.1:62288
I, [2012-07-13T21:10:01.031931 #88528]  INFO -- : [pry-remote-em] client connected to pryem://127.0.0.1:6462/
I, [2012-07-13T21:10:01.032120 #88528]  INFO -- : [pry-remote-em] remote is PryRemoteEm 0.7.0 pryem
I, [2012-07-13T21:10:01.032890 #88528]  INFO -- : [pry-remote-em broker] registered pryem://127.0.0.1:6462/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.125123 #88528]  INFO -- : [pry-remote-em broker] registered pryem://127.0.0.1:6469/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.125487 #88528]  INFO -- : [pry-remote-em broker] registered pryems://127.0.0.1:6467/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.490729 #88528]  INFO -- : [pry-remote-em broker] registered pryems://127.0.0.1:6464/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.583015 #88528]  INFO -- : [pry-remote-em broker] registered pryem://127.0.0.1:1337/ - "#<Foo>"
I, [2012-07-13T21:10:01.674842 #88528]  INFO -- : [pry-remote-em broker] registered pryems://127.0.0.1:6466/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.766813 #88528]  INFO -- : [pry-remote-em broker] registered pryem://127.0.0.1:6468/ - "#<#<Class:0x007f924b9bbee8>>"
I, [2012-07-13T21:10:01.858423 #88528]  INFO -- : [pry-remote-em broker] registered pryems://127.0.0.1:6465/ - "#<#<Class:0x007f924b9bbee8>>"
```

It is possible to have a pry-remote-em server register with a Broker
running on a different host. Just specify the Brokers address in the
PRYEMBROKER environment variable or the :broker_host option passed to #remote_pry_em.

To connect to a broker running on a seperate host with the cli client
just specify it on the command line ``bin/pry-remote-em preym://10.0.0.2:6462/``.
You can then proxy your client connections to remote servers through
that Broker.

The Broker will not run in TLS mode, but it can proxy connections to a
TLS enabled server.


## TLS Encryption

When creating a server pass the tls: true option to enable TLS.

```ruby
obj.remote_pry_em('localhost', :auto, tls: true)
```

If you pass a Hash it will be used to configure the internal TLS handler.

```ruby
obj.remote_pry_em('localhost', :auto, tls: { private_key_file: '/tmp/server.key' })
```
See [EventMachine::Connection#start_tls](http://eventmachine.rubyforge.org/EventMachine/Connection.html#M000296) for the available options.


When the command line client connects to a TLS enabled server it will
automatically use TLS mode even if the user didn't request it.

```bash
$ pry-remote-em pryem://localhost:6462/
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryems
[pry-remote-em] negotiating TLS
[pry-remote-em] TLS connection established
[1] pry(#<Hash>)>
```

To always require a TLS connection give pry-remote-em a pryem*s* URL. If
the server doesn't support TLS the connection will be terminated.

```bash
$ pry-remote-em pryems://localhost:6468/
[pry-remote-em] client connected to pryem://127.0.0.1:6468/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryem
[pry-remote-em] connection failed
[pry-remote-em] server doesn't support required scheme "pryems"
[pry-remote-em] session terminated
```


## User Authentication

### Server

 If the service is started with the :auth option it will require all
clients to authenticate on connect. The :auth option can be a Hash, proc
or any object that responds to #call.

#### Auth with a Hash
```ruby
auth_hash = { 'caleb' => 'crane', 'john' => 'lowski' }
obj       = { encoding: __ENCODING__, weather: :cloudy }
EM.run do
  obj.remote_pry_em('localhost', :auto, tls: true, auth: auth_hash)
end
```

#### Auth with a lambda
```ruby
require 'net/ldap'
ldap_anon = lambda do |user, pass|
  ldap = Net::LDAP.new host: '10.0.0.1', port: 389, auth: { method: :simple, username: user, password: pass }
  ldap.bind
end
obj       = { encoding: __ENCODING__, weather: :cloudy }
EM.run do
  obj.remote_pry_em('localhost', :auto, tls: true, auth: ldap_anon)
end
```

#### Auth with an object
```ruby
class Authenticator
  def initialize(db)
    @db = db
  end
  def call(user, pass)
    @db[user] && @db[user] == pass
  end
end

obj       = { encoding: __ENCODING__, weather: :cloudy }
EM.run do
  obj.remote_pry_em('localhost', :auto, tls: true, auth: Authenticator.new(auth_hash))
end
```


### Client

The included command line client ``pry-remote-em`` can take a username
and/or password as part of the url argument. If either a username or
password is not supplied, but required by the server it will prompt for
them.

```shell
$ pry-remote-em pryems://localhost:6464/
[pry-remote-em] client connected to pryem://127.0.0.1:6464/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryems
[pry-remote-em] negotiating TLS
[pry-remote-em] TLS connection established
user: caleb
caleb's password: *****
[1] pry(#<Hash>)>
```


```shell
$ pry-remote-em pryems://caleb@localhost:6464
[pry-remote-em] client connected to pryem://127.0.0.1:6464/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryems
[pry-remote-em] negotiating TLS
[pry-remote-em] TLS connection established
caleb's password: *****
[1] pry(#<Hash>)> exit
```

```shell
$ pry-remote-em pryems://caleb:crane@localhost:6464
[pry-remote-em] client connected to pryem://127.0.0.1:6464/
[pry-remote-em] remote is PryRemoteEm 0.4.0 pryems
[pry-remote-em] negotiating TLS
[pry-remote-em] TLS connection established
[1] pry(#<Hash>)> exit
```


## Tab Completion

  Tab completion candidates will be retrieved from the server and
presented on the client side.

```ruby
$ bin/pry-remote-em pryems:///
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 0.2.0 pryems
[1] pry(#<Hash>)> key (^TAB ^TAB)
key   key?  keys
[1] pry(#<Hash>)> keys
=> [:encoding]
```

## Paging

The standard Pry pager is supported through the included client.

```ruby
[1] pry(#<Hash>)> ENV
=> {"COMMAND_MODE"=>"unix2003",
 "DISPLAY"=>"/tmp/launch-0EGhJW/org.x:0",
 "EDITOR"=>"mvim -f --nomru -c \"au VimLeave * !open -a Terminal\"",
 "GEM_HOME"=>"/Users/caleb/.rvm/gems/ruby-1.9.2-p290",
 "GEM_PATH"=>
  "/Users/caleb/.rvm/gems/ruby-1.9.2-p290:/Users/caleb/.rvm/gems/ruby-1.9.2-p290@global",
 "GREP_COLOR"=>"1;32",
 "GREP_OPTIONS"=>"--color=auto",
 "HOME"=>"/Users/caleb",
 "IRBRC"=>"/Users/caleb/.rvm/rubies/ruby-1.9.2-p290/.irbrc",
 "LC_CTYPE"=>"",
 "LOGNAME"=>"caleb",
 "LSCOLORS"=>"Gxfxcxdxbxegedabagacad",
:
```

## Sandbox

The `PryRemoteEm::Sandbox` class introduced to help in case when you
do not mush interested in console's executing context but just want to
access a remote server's "control panel" with usefull methods and
without worrying about breaking some object's internal state.

To use sandbox just run `PryRemoteEm::Server.run` instead of
`binding.remote_pry_em`. You can include any modules with your
application's business logic in this class to get real "control panel"
for your program.

The simple example:

```ruby
# Microservice A, a.rb

require 'bundler'
Bundler.require

DB = Sequel.sqlite

module ControlPanel
  def u(id)
    DB[:users].find(id)
  end

  def ban(id)
    DB[:users].where(id: id).update u(id).merge('status' => 'banned')
  end
end

PryRemoteEm::Sandbox.include ControlPanel

EventMachine.run do
  trap(:INT) { EventMachine.stop }

  PryRemoteEm::Server.run name: 'Microservice A', port: :auto, remote_broker: true, details: { environment: 'staging' }
end
```

```ruby
# Microservice B, b.rb

require 'bundler'
Bundler.require

module Transport
  # ...
end

module ControlPanel
  def ping(microservice)
    Transport.send_ping(microservice)
  end
end

PryRemoteEm::Sandbox.include ControlPanel

EventMachine.run do
  trap(:INT) { EventMachine.stop }

  PryRemoteEm::Server.run name: 'Microservice B', port: :auto, remote_broker: true, details: { environment: 'staging' }
end
```

Then, in shell:

```shell
$ pry-remote-em-broker > /dev/null &
$ ruby a.rb > /dev/null &
$ ruby b.rb > /dev/null &
$
$ pry-remote-em -P --sn -d environment
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
------------------------------------------
|     |  name            |  environment  |
------------------------------------------
|  1  |  Microservice A  |  staging      |
|  2  |  Microservice B  |  staging      |
------------------------------------------
(q) to quit; (r) to refresh; (c) to connect without proxy
proxy to: 1
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
[1] Microservice A (sandbox)> u 13
=> {"id"=>13, "violations"=>4, "status"=>"active"}
[2] Microservice A (sandbox)> @my_bad_user = _
=> {"id"=>13, "violations"=>4, "status"=>"active"}
[3] Microservice A (sandbox)> ban 13 # You can use control panel to work with some business cases
=> 1
[4] Microservice A (sandbox)> exit
[pry-remote-em] session terminated
$
$ pry-remote-em pryem://127.0.0.1:6463
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
[1] Microservice A (sandbox)> @my_bad_user
=> {"id"=>13, "violations"=>4, "status"=>"banned"}
[2] Microservice A (sandbox)> exit
[pry-remote-em] session terminated
$
$ pry-remote-em pryem://127.0.0.1:6464
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
[1] Microservice A (sandbox)> ping :A # Or you can use it to check infrastructure and perform custom communications between servers
=> "pong"
[2] Microservice A (sandbox)> exit
[pry-remote-em] session terminated
```

In sandbox you have those possibilities "out of the box":

* `puts`, `putc`, `print`, `p` and `pp` methods almost as you expected.
In other contexts they will use server's STDOUT, but in sandbox they
will send all the data to client. Remember, you'll lost those methods
out of the sandbox context:

```shell
$ pry-remote-em pryem://127.0.0.1:6463
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
[1] Demo Server (sandbox)> puts 'Hello World' # It works!
Hello World
=> nil
[2] Demo Server (sandbox)> Object.new.instance_eval { puts "Hello World" } # Do not work
=> nil
[3] Demo Server (sandbox)> cd Object.new
[4] Demo Server (#<Object>):1> puts "Hello World" # Do not work
=> nil
```

* `any_errors?`, `last_error` and `last_errors` methods in sandbox
context with `PryRemoteEm::Sandbox.add_error` method from your code
to help you store all the bugs and debug it in the bug's execution
context. It also integrated with `wtf?` command. For example:

```ruby
require 'bundler'
Bundler.require

def safe_handler(source_binding)
  yield
rescue => exception
  PryRemoteEm::Sandbox.add_error(exception, source_binding)
  raise
end

def danger_mathod(a, b)
  safe_handler(binding) do
    a / b
  end
end

EventMachine.run do
  trap(:INT) { EventMachine.stop }

  EventMachine.error_handler do |exception|
    PryRemoteEm::Sandbox.add_error(exception)
  end

  EventMachine.add_timer(5) { danger_mathod 1, 0 }

  PryRemoteEm::Server.run name: 'Demo Server', details: { hostname: 'local' }
end
```

Then, in shell:

```shell
$ pry-remote-em -P --sn -d hostname
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
------------------------------------
|     |  name         |  hostname  |
------------------------------------
|  1  |  Demo Server  |  local     |
------------------------------------
(q) to quit; (r) to refresh; (c) to connect without proxy
proxy to: 1
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
[1] Demo Server (sandbox)> any_errors?
=> true
[2] Demo Server (sandbox)> last_error
=> #<ZeroDivisionError: divided by 0>
[3] Demo Server (sandbox)> wtf?
Exception: ZeroDivisionError: divided by 0
--
0: demo_server.rb:13:in `/'
1: demo_server.rb:13:in `block in danger_mathod'
2: demo_server.rb:5:in `safe_handler'
3: demo_server.rb:12:in `danger_mathod'
4: demo_server.rb:24:in `block (2 levels) in <main>'
5: /usr/local/lib/ruby/gems/2.4.0/gems/eventmachine-1.2.7/lib/eventmachine.rb:195:in `run_machine'
6: /usr/local/lib/ruby/gems/2.4.0/gems/eventmachine-1.2.7/lib/eventmachine.rb:195:in `run'
7: demo_server.rb:17:in `<main>'
[4] Demo Server (sandbox)> cd last_error.source_binding
[5] Demo Server (main):1> whereami

From: /Users/user/Projects/demo/demo_server.rb @ line 12 Object#danger_mathod:

    11: def danger_mathod(a, b)
 => 12:   safe_handler(binding) do
    13:     a / b
    14:   end
    15: end

[6] Demo Server (main):1> ls
self.methods: inspect  to_s
locals: _  __  _dir_  _ex_  _file_  _in_  _out_  _pry_  a  b
[7] Demo Server (main):1> a
=> 1
[8] Demo Server (main):1> b
=> 0
```

* `server` method to access PryRemoteEm::Server description object.
For example, it can be useful for changing `details`:

```ruby
require 'bundler'
Bundler.require

module HealthChecker
  # ...
end

EventMachine.run do
  trap(:INT) { EventMachine.stop }

  PryRemoteEm::Server.run name: 'Demo Server', heartbeat_interval: 1, details: { hand_check: false }
end
```

Then, in shell:

```shell
$ pry-remote-em -P --sn -d hand_check
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
--------------------------------------
|     |  name         |  hand_check  |
--------------------------------------
|  1  |  Demo Server  |  true        |
|  2  |  Demo Server  |  true        |
|  3  |  Demo Server  |  false       |
|  4  |  Demo Server  |  false       |
|  5  |  Demo Server  |  false       |
--------------------------------------
(q) to quit; (r) to refresh; (c) to connect without proxy
proxy to: 3
[1] Demo Server (sandbox)> HealthChecker.all_ok?
=> true
[2] Demo Server (sandbox)> server[:details][:hand_check] = true
=> true
[3] Demo Server (sandbox)> exit
[pry-remote-em] session terminated
$
$ sleep 1
$ pry-remote-em -P --sn -d hand_check
[pry-remote-em] client connected to pryem://127.0.0.1:6462/
[pry-remote-em] remote is PryRemoteEm 1.0.0 pryem
--------------------------------------
|     |  name         |  hand_check  |
--------------------------------------
|  1  |  Demo Server  |  true        |
|  2  |  Demo Server  |  true        |
|  3  |  Demo Server  |  true        |
|  4  |  Demo Server  |  false       |
|  5  |  Demo Server  |  false       |
--------------------------------------
(q) to quit; (r) to refresh; (c) to connect without proxy
proxy to:
```

## Messaging
It is possible for each pry-remote-em service to host multiple
simultaneous connections. You can send messages to other connections
with the '^' and '^^' prefix.

The '^' prefix will send the message to connections on the same object.
the '^^' prefix will send the message to all connections in the current
process.

Message will not be displayed by the clients until the presses enter.

## Authentication Event Callbacks
Available events are:

 - auth_attempt - called each time authentication is attempted
 - auth_fail    - called each time authentication fails
 - auth_ok      - called each time authentication succeeds

```ruby
log = ::Logger.new('/var/log/auth.pry.log')
obj.new.remote_pry_em('0.0.0.0', :auto, tls: true, auth: auth_hash) do |pry|
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
```

## Shell Commands
Unless the pry-remote-em service is started with the ``allow_shell_cmds:
false`` option set it will spawn sub processes for any command prefixed
with a '.'.

```
[1] pry(#<#<Class:0x007fe0be072618>>)> .uname -a
Darwin kiff.local 11.3.0 Darwin Kernel Version 11.3.0: Thu Jan 12 18:47:41 PST 2012; root:xnu-1699.24.23~1/RELEASE_X86_64 x86_64
```

Interactive commands like ``vim`` will probably not behave
appropriately.


If the server was started with the ``allow_shell_cmds: false`` option then
all shell commands will be met with a rejection notice.

```
[1] pry(#<#<Class:0x007fe0be072618>>)> .ls
shell commands are not allowed by this server
```

The server will also log whenever a user attempts to execute a shell command.

```
W, [2012-02-11T19:21:27.663941 #36471]  WARN -- : executing shell command 'ls -al' for  (127.0.0.1:63878)
```

```
E, [2012-02-11T19:23:40.770380 #36471] ERROR -- : refused to execute shell command 'ls' for caleb (127.0.0.1:63891)
```

# Environment variables

* PRYEMNAME - pry server name to show in broker's list, default - target object's inspect
* PRYEMURL - pry server URL to show in broker's list, default - pryem://#{server_host}:#{server_port}/
* PRYEMHOST - host to bind pry server, default - 127.0.0.1
* PRYEMPORT - port to bind pry server, default - 6463
* PRYEMBROKER - host to bind pry broker, default - 127.0.0.1
* PRYEMBROKERPORT - port to bind pry broker, default - 6462
* PRYEMREMOTEBROKER - start server without starting broker, default - broker starting with server
* PRYEMNOPAGER - disable paging on long output, default - pager enabled
* PRYEMNEGOTIMEOUT - connection negotiation timeout in seconds, default - 15
* PRYEMHBSEND - server to broker heartbeat interval in seconds, default - 15
* PRYEMHBCHECK - heartbeat check on broker interval in seconds, default - 20
* PRYEMBROKERTIMEOUT - reconnect to broker timeout in seconds, default - 3
* PRYEMSANDBOXERRORS - number of errors to store in sandbox, default - 100

# Missing Features

  - HTTP Transport ([ticket](https://github.com/simulacre/pry-remote-em/issues/12))
  - SSH key based authentication
  - Looking for connected users and their history

# Issues

 Please post any bug reports or feature requests on [Github](https://github.com/simulacre/pry-remote-em/issues)

# Copyright

Copyright (c) 2012 Caleb Crane

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
