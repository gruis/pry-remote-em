# 1.0.0

## Breaking changes

* **BREAKING CHANGE** Change `!` and `!!` messaging commands to `^` and `^^` to avoid confusing with Pry's built in `!` command and Ruby's `not` semantics
* **BREAKING CHANGE** Change `PryRemoteEm::Server.run` method signature to hash-only form (`remote_pry_em` method's signature didn't changed)
* **BREAKING CHANGE** Change `allow_shell_cmds` setting to `true` by default instead of `false`, because most of projects does not use $SAFE and any shell command can be run from Ruby code with `system` call or backticks, so this option is illusion in most cases
* **BREAKING CHANGE** `PryRemoteEm::Server.run` returns whole server description instead of URL
* **BREAKING CHANGE** Rename public constants to avoid confusing

## Features

* Add `PryRemoteEm::Sandbox` as target by default, see Readme for details
* Add proxy-by-default setting to CLI
* Add possibility to use environment variables on CLI connection
* Add more environment variables to control server without code changing (described in readme)
* Add support for empty environment variables and nil arguments on server start
* Add possibility to set external url for server (to use lib with NAT or Docker) using `PRYEMURL` or `external_url` option
* Add ability to use custom server name using `PRYEMNAME` environment variable or `name` option (and displaying it in the prompt)
* Add ability to start server without starting broker using `PRYEMREMOTEBROKER` environment variable or `remote_broker` option
* Add `pry-remote-em-broker` binary to start broker without starting server
* Add `Object#pry_remote_em` alias to `Object#remote_pry_em` to avoid common confusing
* Add support for options hash as first argument instead of third in `Object#remote_pry_em`
* Add local history loading on session start
* Add support for `pry-coolline` (just install this gem to make it work)
* Add support for several URIs per one server (when binding to 0.0.0.0)
* Add option to ignore localhost urls in the list (useful when server binding to 0.0.0.0 in Docker, where localhost is useless)
* Add support for `details` option on server start and corresponding CLI option to display some usefull information about server instead or url in broker table (for example, health status, which can be updated on every heartbeat via details hash mutating)

## Fixes

* Fix proxy, it didn't work at all
* Fix interative shell commands, they didn't work at all
* Fix `libc++abi.dylib: Pure virtual function called!` error on client disconnecting
* Fix strange buffer bugs on long output over network using MessagePack protocol instead of JSON
* Fix console crash on pager quit
* Fix console crash on Ctrl+C (now it's clears the buffer like in native Pry)
* Fix IPv6 localhost crash
* Fix missing requires when using broker without server
* Fix port access check when using environment variables
* Fix strange effects when registering in broker from Docker (now broker use UUID as a key instead of URI)
* Fix message `broker connection unbound starting a new one` on EventMachine stopping
* Fix unregistering in broker by timeout only, now servers unregister instantly after closing connection
* Fix interative shell commands echo printing
* Fix unknown shell command problem (now valid `command not found` message is printing)
* Fix behaviour on empty input, now it's exactly like as in native Pry
* Fix saving empty strings in history

## Chore

* Add ruby-termios to runtime dependencies to avoid confusing `unable to load keyboard dependencies` message
* Bump dependencies versions
* Remove useless return values from inner methods
* Add stable 3 seconds timeout on broker reconnection, not random one
* Require `pry-remote-em/server` by defaults
* Correct README for default broker port
* Use single quotes by default
* Use Ruby 1.9 hash syntax by default
* Use semantic versioning, starting at 1.0.0 (since we're using it in production for a long time already)

# 0.7.5

* [#42](https://github.com/gruis/pry-remote-em/pull/42) - Use bytesize String method instead of length in protocol. [distorhead](https://github.com/distorhead)

# 0.7.4

* [#40](https://github.com/gruis/pry-remote-em/pull/40) - require 'pry', not its parts [rking](https://github.com/rking)
* [#39](https://github.com/gruis/pry-remote-em/pull/39) - stagger_output needs Pry::Pager to be loaded in the parent scope [pcmantz](https://github.com/pcmantz)

# 0.7.3

* Broker listens at 6462 everything else starts at 6463
* cli assumes port 6462 when not specified

# 0.7.2

* Broker.run yields to a block when broker connection has been established

# 0.7.1

* server list can be filtered by host, port, name, or SSL support
* server list can be sorted by host, port, name, or SSL support
* cli assumes port 6461 when not specified
* cli accepts -c and -p options to immediately connect or proxy from the broker to a server matching the name specified on the command line
* closes #37 loosens pry version requirement
* client sorts server list by host address
* when registering 0.0.0.0 with a Broker register each interface instead

# 0.7.0

* fixes #21 version matching between client and server allow differences in patch levels
* fixes #31 client reports own version when incompatible with server
* client supports vi mode: rb-readline replaced by readline
* fixes #31 termios is no longer a hard requirement: shell commands will be disabled without it
* adds PryRemoteEm.servers and PryRemoteEm.stop_server
* broker can proxy requests to local or remote servers that have registered with it
* closes #11 all servers will attempt to register with a broker; client will retrieve list of servers from the broker and present a menu to the user by default
* when specifying a specific port to listen on the option :port_fail can be set to :auto; if binding fails attempt to bind on the next port
* server.run returns a url (String) with the scheme, host and port of the listening server
* json specific parts of wire protocol are abstracted away from client and server
* json proto is a bit more robust: delimeter can be a part of data and CRC is performed

# 0.6.2

* handle reset command appropriately

# 0.6.1

* messages are tagged with user that sent them if authentication is being used

# 0.6.0

* adds shell command support
* adds auth event callbacks
* adds configurable logger

# 0.5.0

* adds simple messaging with '!' and '!!'

# 0.4.3

* fixes https://github.com/gruis/pry-remote-em/issues/26
* fixes https://github.com/gruis/pry-remote-em/issues/24

# 0.4.2

* fixes https://github.com/gruis/pry-remote-em/issues/23

# 0.4.1

* empty lines don't cause termination

# 0.4.0

* User/Pass authentication
* TLS support
* Paging support
* Tab completion
