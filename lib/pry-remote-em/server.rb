require 'pry'
require 'socket'
require 'logger'
require 'securerandom'
require 'pry-remote-em'
require 'pry-remote-em/broker'
require 'pry-remote-em/server/shell_cmd'
require 'pry-remote-em/sandbox'

# How it works with Pry
#
# When PryRemoteEm.run is called it registers with EventMachine for a given ip
# and port. When a connection is received EM yields an instance of PryRemoteEm,
# we start a Fiber (f1) then call Pry.start specifying the Server instance as the
# input and output object for Pry. The Pry instance that is created goes into
# its REPL.  When it gets to the read part it calls @input.readline
# (PryRemoteEm#readline) and passes a prompt, e.g., [1] pry(#<Foo>)>.
#
# PryRemoteEm#readline calls #send_data with the prompt then yields from the
# current Fiber (f1); the one we started when EventMachine yielded to us. The root
# Fiber is now active again. At some point, the root Fiber receives data from
# the client. It calls #receive_data in our Server instance. That instance then
# resumes the Fiber (f1) that was waiting for #readline to finish.
#
# Inside the resumed Fiber (f1) PryRemoteEm#readline returns the recieved data
# to the instance of Pry, which continues its REPL. Pry calls #puts, or #print
# or #write on its output object (PryRemoteEm). We send that data out to the client
# and immediately return. Pry then calls PryRemoteEm#readline again and again
# we send the prompt then immediately yield back to the root Fiber.
#
# Pry just interacts with PryRemoteEm as if it were any other blocking Readline
# object. The important bit is making sure that it is started in a new Fiber that
# can be paused and resumed as needed. PryRemoteEm#readline pauses it and
# PryRemoteEm#receive_raw resumes it.
#
# Reference:
# http://www.igvita.com/2010/03/22/untangling-evented-code-with-ruby-fibers/
module PryRemoteEm
  class << self
    # Local PryRemoteEm servers, including EM signatures, indexed by id. Each
    # signature can be used with high level EM methods like EM.stop_server or
    # EM.get_sockname. If a server has been stopped EM.get_sockname will return
    # nil for that server's signature.
    def servers
      @servers ||= {}
    end

    # Safely stop one or more PryRemoteEm servers and remove them from the list
    # of servers.
    # @param [String, nil] argument id, url or name, use `nil` to stop them all
    # @return [Hash] stopped servers if they were
    def stop_server(argument = nil)
      servers_to_stop = if argument
        servers.select do |id, description|
          argument == id || description[:urls].include?(argument) || argument == description[:name]
        end
      else
        servers
      end

      servers_to_stop.each do |id, description|
        EM.stop_server(description[:server]) if EM.get_sockname(description[:server])
        Broker.unregister(id)
        servers.delete(id)
      end
    end
  end

  module Server
    include Proto

    class << self
      # Start a pry-remote-em server
      # @param [Hash] options
      # @option options [Object] :target Object to bind Pry session, default - PryRemoteEm::Sandbox instance
      # @option options [String] :host The IP-address to listen on, default - 127.0.0.1 (same as PRYEMHOST environment variable)
      # @option options [Fixnum, String, Symbol] :port The port to listen on - if :auto or 'auto' the next available port will be taken, default - 6463 (same as PRYEMPORT environment variable)
      # @option options [String] :id Server's UUID, will be generated automatically unless you pass it explicitly
      # @option options [Boolean] :tls require SSL encryption, default - false
      # @option options [Logger] :logger Logger for Pry Server, default - STDERR
      # @option options [Proc, Object] :auth require user authentication - see README
      # @option options [Boolean] :allow_shell_cmds Allow shell commands or not, default - true
      # @option options [Integer, Symbol] :port_fail set to :auto to search for available port in range from given port to port + 100, or pass explicit integer to use instaed of 100, default - 1
      # @option options [String] :name Server name to show in broker list, default - object's inspect (same as PRYEMNAME environment variable)
      # @option options [String] :external_url External URL to connect behind firewall, NAT, Docket etc. in form "pryem://my.host:6463", default - use given host and port and expand it to all interfaces in case of 0.0.0.0 (same as PRYEMURL environment variable)
      # @option options [Integer] :heartbeat_interval Interval to send heartbeats and updated details to broker, default - 15 (same as PRYEMHBSEND environment variable)
      # @option options [Boolean] :remote_broker Connect to remote broker instead of starting local one, default - false (same as PRYEMREMOTEBROKER environment variable)
      # @option options [String] :broker_host Broker host to connect to, default - localhost
      # @option options [String] :broker_port Broker port to connect to, default - 6462
      # @option options [Hash] :details Optional details to pass to broker and show in table (should consist of string/symbol keys and simple serializable values)
      def run(options = {}, &block)
        description = options.dup
        description[:target] ||= PryRemoteEm::Sandbox.new
        description[:host] ||= ENV['PRYEMHOST'].nil? || ENV['PRYEMHOST'].empty? ? DEFAULT_SERVER_HOST : ENV['PRYEMHOST']
        determine_port_and_tries(description)
        determine_name(description)
        description[:id] ||= SecureRandom.uuid
        description[:logger] ||= ::Logger.new(STDERR)
        description[:external_url] ||= ENV['PRYEMURL'] || "#{description[:tls] ? 'pryems' : 'pryem'}://#{description[:host]}:#{description[:port]}/"
        description[:details] ||= {}
        description[:allow_shell_cmds] = true if description[:allow_shell_cmds].nil?
        description[:heartbeat_interval] ||= ENV['PRYEMHBSEND'].nil? || ENV['PRYEMHBSEND'].empty? ? HEARTBEAT_SEND_INTERVAL : ENV['PRYEMHBSEND']
        description[:urls] = expand_url(description[:external_url])
        description[:server] = start_server(description, &block)
        description[:logger].info("[pry-remote-em] listening for connections on #{description[:external_url]}")
        PryRemoteEm.servers[description[:id]] = description
        register_in_broker(description)
        return description
      end

      # The list of pry-remote-em connections for a given object, or the list of all pry-remote-em
      # connections for this process.
      # The peer list is used when broadcasting messages between connections.
      def peers(obj = nil)
        @peers ||= {}
        obj.nil? ? @peers.values.flatten : (@peers[obj] ||= [])
      end

      # Record the association between a given object and a given pry-remote-em connection.
      def register(obj, peer)
        peers(obj).tap { |plist| plist.include?(peer) || plist.push(peer) }
      end

      # Remove the association between a given object and a given pry-remote-em connection.
      def unregister(obj, peer)
        peers(obj).tap {|plist| true while plist.delete(peer) }
      end

      private

      def determine_port_and_tries(description)
        description[:port] ||= ENV['PRYEMPORT'].nil? || ENV['PRYEMPORT'].empty? ? DEFAULT_SERVER_PORT : ENV['PRYEMPORT']
        description[:port] = :auto if description[:port] == 'auto'
        description[:port] = description[:port].to_i if description[:port].kind_of?(String)
        description[:tries] = [description[:port], description[:port_fail]].include?(:auto) ? 100 : description[:port_fail] || 1
        description[:port] = DEFAULT_SERVER_PORT if description[:port] == :auto
        # TODO raise a useful exception not RuntimeError
        raise "root permission required for port below 1024 (#{port})" if description[:port] < 1024 && Process.euid != 0
      end

      def determine_name(description)
        description[:name] ||= ENV['PRYEMNAME']
        if description[:name].nil?
          object = description[:target]
          inner_object = object.kind_of?(Binding) ? object.send(:eval, 'self') : object
          description[:name] = Pry.view_clip(inner_object)
        else
          description[:custom_name] = true
        end
        description[:name] = description[:name].first(57) + '...' if description[:name].size > 60
      end

      def expand_url(url)
        return Array(url) if (uri = URI.parse(url)).host != '0.0.0.0'
        Socket.ip_address_list.select(&:ipv4?).map(&:ip_address).map do |ip|
          uri.clone.tap { |uri_copy| uri_copy.host = ip }.to_s
        end
      end

      def start_server(description, &block)
        EM.start_server(description[:host], description[:port], PryRemoteEm::Server, description) do |pre|
          Fiber.new do
            begin
              yield pre if block_given?
              Pry.hooks.add_hook :when_started, pre do |target, options, pry|
                pry.pager = false
                pry.config.prompt_name = description[:name] + ' ' if description[:custom_name]
                if description[:target].is_a? PryRemoteEm::Sandbox
                  description[:target].pry = pry
                  description[:target].server = description
                  pry.last_exception = description[:target].last_error if description[:target].any_errors?
                end
                description[:pry] = pry
              end
              Pry.start(description[:target], input: pre, output: pre)
            ensure
              pre.close_connection
              Pry.hooks.delete_hook :when_started, pre
            end
          end.resume
        end
      rescue => error
        if error.message.include?('port is in use') && description[:tries] > 1
          description[:tries] -= 1
          description[:port] += 1
          retry
        end
        raise "can't bind to #{description[:host]}:#{description[:port]} - #{error}"
      end

      def register_in_broker(description)
        broker_description = { id: description[:id], urls: description[:urls], name: description[:name], details: description[:details] }
        broker_options = { tls: description[:tls], remote_broker: description[:remote_broker], logger: description[:logger] }
        Broker.run(description[:broker_host], description[:broker_port], broker_options) do |broker|
          broker.register(broker_description)

          rereg = EM::PeriodicTimer.new(description[:heartbeat_interval]) do
            EM.get_sockname(description[:server]) ? broker.register(broker_description) : nil #rereg.cancel
          end
        end
      end
    end # class << self

    def initialize(opts = {})
      @obj              = opts[:target]
      @opts             = opts
      @allow_shell_cmds = opts[:allow_shell_cmds]
      @log              = opts[:logger] || ::Logger.new(STDERR)
      # Blocks that will be called on each authentication attempt, prior checking the credentials
      @auth_attempt_cbs = []
      # All authentication attempts that occured before an auth callback was registered
      @auth_attempts    = []
      # Blocks that will be called on each failed authentication attempt
      @auth_fail_cbs    = []
      # All failed authentication attempts that occured before an auth callback was reigstered
      @auth_fails       = []
      # Blocks that will be called on successful authentication attempt
      @auth_ok_cbs      = []
      # All successful authentication attemps that occured before the auth ok callbacks were registered
      @auth_oks         = []

      # The number maximum number of authentication attempts that are permitted
      @auth_tries       = 5
      # Data to be sent after the user successfully authenticates if authentication is required
      @after_auth       = []
      return unless (a = opts[:auth])
      if a.is_a?(Proc)
        return fail("auth handler Procs must take two arguments not (#{a.arity})") unless a.arity == 2
        @auth = a
      elsif a.respond_to?(:call)
        return fail("auth handler must take two arguments not (#{a.method(:call).arity})") unless a.method(:call).arity == 2
        @auth = a
      else
        return error('auth handler objects must respond to :call, or :[]') unless a.respond_to?(:[])
        @auth = lambda {|u,p| a[u] && a[u] == p }
      end
    end

    def url
      port, host = Socket.unpack_sockaddr_in(get_sockname)
      "#{@opts[:tls] ? 'pryems' : 'pryem'}://#{host}:#{port}/"
    end

    def post_init
      @lines = []
      @auth_required  = @auth
      @port, @ip        = Socket.unpack_sockaddr_in(get_peername)
      @log.info("[pry-remote-em] received client connection from #{@ip}:#{@port}")
      # TODO include first level prompt in banner
      send_banner("PryRemoteEm #{VERSION} #{@opts[:tls] ? 'pryems' : 'pryem'}")
      @log.info("#{url} PryRemoteEm #{VERSION} #{@opts[:tls] ? 'pryems' : 'pryem'}")
      @opts[:tls] ? start_tls : (@auth_required && send_auth(false))
      PryRemoteEm::Server.register(@obj, self)
    end

    def start_tls
      @log.debug("[pry-remote-em] starting TLS (#{peer_ip}:#{peer_port})")
      super(@opts[:tls].is_a?(Hash) ? @opts[:tls] : {})
    end

    def ssl_handshake_completed
      @log.info("[pry-remote-em] TLS connection established (#{peer_ip}:#{peer_port})")
      send_auth(false) if @auth_required
    end

    def peer_ip
      return @peer_ip if @peer_ip
      return '' if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_ip
    end

    def peer_port
      return @peer_port if @peer_port
      return '' if get_peername.nil?
      @peer_port, @peer_ip = Socket.unpack_sockaddr_in(get_peername)
      @peer_port
    end

    def receive_clear_buffer
      @opts[:pry].eval_string.replace('')
      @last_prompt = @opts[:pry].select_prompt
      send_last_prompt
    end

    def receive_raw(d)
      return if require_auth

      return send_last_prompt if d.nil?

      if d.empty?
        @lines.push('')
      else
        lines = d.split("\n")
        @lines.push(*lines)
      end

      if @waiting
        f, @waiting = @waiting, nil
        f.resume(@lines.shift)
      end
    end

    # tab completion request
    def receive_completion(c)
      return if require_auth
      send_completion(@compl_proc.call(c))
    end

    def receive_auth(user, pass)
      return send_auth(true) if !@auth || !@auth_required
      return send_auth('auth data must include a user and pass') if user.nil? || pass.nil?
      auth_attempt(user, peer_ip)
      unless (@auth_required = !@auth.call(user, pass))
        @user = user
        auth_ok(user, peer_ip)
        authenticated!
      else
       auth_fail(user, peer_ip)
        if @auth_tries <= 0
          msg = 'max authentication attempts reached'
          send_auth(msg)
          @log.debug("[pry-remote-em] #{msg} (#{peer_ip}:#{peer_port})")
          return close_connection_after_writing
        end
        @auth_tries -= 1
      end
      return send_auth(!@auth_required)
    end

    def receive_msg(m)
      return if require_auth
      peers.each { |peer| peer.send_message(m, @user) }
      send_last_prompt
    end

    def receive_msg_bcast(mb)
      return if require_auth
      peers(:all).each { |peer| peer.send_bmessage(mb, @user) }
      send_last_prompt
    end

    def receive_shell_cmd(cmd)
      return if require_auth
      unless @allow_shell_cmds
        puts "\033[1mshell commands are not allowed by this server\033[0m"
        @log.error("refused to execute shell command '#{cmd}' for #{@user} (#{peer_ip}:#{peer_port})")
        send_shell_result(-1)
        send_last_prompt
      else
        @log.warn("executing shell command '#{cmd}' for #{@user} (#{peer_ip}:#{peer_port})")
        @shell_cmd = EM.popen3(cmd, ShellCmd, self)
      end
    end

    def receive_shell_data(d)
      return if require_auth
      @shell_cmd.send_data(d)
    end

    def receive_shell_sig(type)
      return if require_auth
      @shell_cmd.close_connection if type == :int
    end

    def receive_unknown(j)
      return if require_auth
      warn "received unexpected data: #{j.inspect}"
      send_error("received unexpected data: #{j.inspect}")
      send_last_prompt
    end

    def require_auth
      return false if !@auth_required
      send_auth(false)
      true
    end

    def authenticated!
      while (aa = @after_auth.shift)
        aa.call
      end
    end

    def unbind
      PryRemoteEm::Server.unregister(@obj, self)
      @log.debug("[pry-remote-em] remote session terminated (#{@ip}:#{@port})")
    end

    def peers(all = false)
      plist = (all ? PryRemoteEm::Server.peers : PryRemoteEm::Server.peers(@obj)).clone
      plist.delete(self)
      plist
    end

    def send_last_prompt
      @auth_required ? (after_auth { send_prompt(@last_prompt) }) :  send_prompt(@last_prompt)
    end

    def after_auth(&blk)
      # TODO perhaps replace with #auth_ok
      @after_auth.push(blk)
    end

    # Sends a chat message to the client.
    def send_message(msg, from = nil)
      msg = "#{msg} (@#{from})" unless from.nil?
      @auth_required ? (after_auth {send_msg(msg)}) : send_msg(msg)
    end
    #
    # Sends a chat message to the client.
    def send_bmessage(msg, from = nil)
      msg = "#{msg} (@#{from})" unless from.nil?
      @auth_required ? (after_auth {send_msg_bcast(msg)}) : send_msg_bcast(msg)
    end

    # Callbacks for events on the server

    # Registers a block to call when authentication is attempted.
    # @overload auth_attempt(&blk)
    #   @yield [user, ip] a block to call on each authentication attempt
    #   @yieldparam [String] user
    #   @yieldparam [String] ip
    def auth_attempt(*args, &blk)
      block_given? ? @auth_attempt_cbs << blk : @auth_attempts.push(args)
      while (auth_data = @auth_attempts.shift)
        @auth_attempt_cbs.each { |cb| cb.call(*auth_data) }
      end
    end # auth_attempt(*args, &blk)

    # Registers a block to call when authentication fails.
    # @overload auth_fail(&blk)
    #   @yield [user, ip] a block to call after each failed authentication attempt
    #   @yieldparam [String] user
    #   @yieldparam [String] ip
    def auth_fail(*args, &blk)
      block_given? ? @auth_fail_cbs << blk : @auth_fails.push(args)
      while (fail_data = @auth_fails.shift)
        @auth_fail_cbs.each { |cb| cb.call(*fail_data) }
      end
    end # auth_fail(*args, &blk)

    # Registers a block to call when authentication succeeds.
    # @overload auth_ok(&blk)
    #   @yield [user, ip] a block to call after each successful authentication attempt
    #   @yieldparam [String] user
    #   @yieldparam [String] ip
    def auth_ok(*args, &blk)
      block_given? ? @auth_ok_cbs << blk : @auth_oks.push(args)
      while (ok_data = @auth_oks.shift)
        @auth_ok_cbs.each { |cb| cb.call(*ok_data) }
      end
    end # auth_fail(*args, &blk)

    def send_error(msg)
      puts "\033[31m#{msg}\033[0m"
    end

    # Methods that make Server compatible with Pry

    def readline(prompt)
      @last_prompt = prompt
      @auth_required ? (after_auth { send_prompt(prompt) }) : send_prompt(prompt)
      return @lines.shift unless @lines.empty?
      @waiting = Fiber.current
      return Fiber.yield
    end

    def print(val)
      @auth_required ? (after_auth { send_raw(val) }) : send_raw(val)
    end
    alias :write :print

    def puts(data = '')
      s = data.to_s
      print(s[0] == "\n" ? s : s + "\n")
    end

    def completion_proc=(compl)
      @compl_proc = compl
    end

    def tty?
      true # might be a very bad idea ....
    end

    def flush
      true
    end
  end # module::Server
end # module::PryRemoteEm
