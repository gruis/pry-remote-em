require 'uri'
require 'pry-remote-em'
require 'pry-remote-em/client/keyboard'
require 'pry-remote-em/client/generic'
require 'pry-remote-em/client/interactive_menu'
require 'pry'
require 'pry-coolline' rescue require 'readline'

module PryRemoteEm
  module Client
    include EM::Deferrable
    include Generic
    include InteractiveMenu
    include Pry::Helpers::BaseHelpers

    class << self
      def start(host = nil, port = nil, opts = {})
        EM.connect(host || PryRemoteEm::DEFAULT_SERVER_HOST, port || PryRemoteEm::DEFAULT_SERVER_PORT, PryRemoteEm::Client, opts) do |c|
          c.callback { yield if block_given? }
          c.errback do |e|
            Kernel.puts "[pry-remote-em] connection failed\n#{e}"
            yield(e) if block_given?
          end
        end
      end
    end # class << self

    attr_reader :opts

    def initialize(opts = {})
      @opts = opts
      if (a = opts[:auth])
        if a.respond_to?(:call)
          @auth = a
        else
          @auth = lambda { a }
        end
      end
    end

    def post_init
      @input = if defined?(PryCoolline)
        PryCoolline.make_coolline
      else
        Pry.history.load if Pry.config.history.should_load
        Readline
      end
      @input.completion_proc = method(:auto_complete)
    end

    def ssl_handshake_completed
      log.info('[pry-remote-em] TLS connection established')
      @opts[:tls] = true
    end

    def unbind
      if (uri = @reconnect_to)
        @reconnect_to = nil
        tls       = uri.scheme == 'pryems'
        log.info("\033[35m[pry-remote-em] connection will not be encrypted\033[0m")  if @opts[:tls] && !tls
        @opts[:tls]   = tls
        @tls_started  = false
        reconnect(uri.host, uri.port)
      else
        @unbound = true
        log.info('[pry-remote-em] session terminated')
        # prior to 1.0.0.b4 error? returns true here even when it's not
        return succeed if Gem.loaded_specs['eventmachine'].version < Gem::Version.new('1.0.0.beta4')
        error? ? fail : succeed
      end
    end

    def receive_banner(name, version, scheme)
      # Client::Generic#receive_banner
      if super(name, version, scheme)
        start_tls if @opts[:tls]
      end
    end

    def receive_server_list(list)
      if list.empty?
        log.info("\033[33m[pry-remote-em] no servers are registered with the broker\033[0m")
        Process.exit
      end
      url, proxy = choose_server(list)
      return unless url
      uri = URI.parse(url)
      if proxy
        @opts[:tls]  = uri.scheme == 'pryems'
        @negotiated  = false
        @tls_started = false
        return send_proxy_connection(url)
      end
      @reconnect_to = uri
      close_connection
    end

    def receive_auth(a)
      return fail a if a.is_a?(String)
      return authenticate if a == false
      @authenticated = true if a == true
    end

    def receive_msg(m)
      Kernel.puts "\033[1m! msg: " + m + "\033[0m"
    end

    def receive_msg_bcast(mb)
      Kernel.puts "\033[1m!! msg: " + mb + "\033[0m"
    end

    def receive_shell_cmd(c)
      Kernel.puts c
    end

    def receive_shell_result(c)
      if @keyboard
        @keyboard.bufferio(true)
        @keyboard.close_connection
      end
      if c == 255 || c == 127
        Kernel.puts 'command not found'
      end
    end

    # TODO detect if the old pager behavior of Pry is supported and use it
    # through Pry.pager. If it's not then use the SimplePager.
    def pager
      pager_class = ENV['PRYEMNOPAGER'] ? Pry::Pager::NullPager : @opts[:pager] || Pry::Pager::SimplePager
      @pager ||= pager_class.new(Pry::Output.new(Pry))
    end

    def receive_raw(r)
      pager.write(r)
    rescue Pry::Pager::StopPaging
      warn '[pry-remote-em] stop paging is not implemented, use PRYEMNOPAGER environment variable to avoid paging at all'
    end

    def receive_unknown(j)
      warn "[pry-remote-em] received unexpected data: #{j.inspect}"
    end

    def authenticate
      return fail('[pry-remote-em] authentication required') unless @auth
      return fail("[pry-remote-em] can't authenticate before negotiation complete") unless @negotiated
      user, pass = @auth.call
      return fail("[pry-remote-em] expected #{@auth} to return a user and password") unless user && pass
      send_auth([user, pass])
    end # authenticate

    def auto_complete(word)
      word = word.completed_word if defined?(Coolline) && word.kind_of?(Coolline)

      @waiting = Thread.current
      EM.next_tick { send_completion(word) }
      sleep
      c = Thread.current[:completion]
      Thread.current[:completion] = nil
      c
    end

    def receive_completion(c)
      return unless @waiting
      @waiting[:completion] = c
      @waiting, t = nil, @waiting
      t.run
    end

    def receive_prompt(p)
      readline(p)
    end

    def readline(prompt = @last_prompt)
      @last_prompt = prompt
      if @negotiated && !@unbound
        operation = proc do
          thread = Thread.current
          old_trap = Signal.trap(:INT) { thread.raise Interrupt }
          begin
            @input.readline(prompt)
          rescue Interrupt
            puts
            retry
          ensure
            Signal.trap(:INT, old_trap)
          end
        end

        callback  = proc do |l|
          add_to_history(l) unless l == ''

          if l.nil?
            readline
          elsif '!!' == l[0..1]
            send_msg_bcast(l[2..-1])
          elsif '!' == l[0]
            send_msg(l[1..-1])
          elsif '.' == l[0]
            send_shell_cmd(l[1..-1])
            if Gem.loaded_specs['eventmachine'].version < Gem::Version.new('1.0.0.beta4')
              Kernel.puts "\033[1minteractive shell commands are not well supported when running on EventMachine prior to 1.0.0.beta4\033[0m"
            else
              @keyboard = EM.open_keyboard(Keyboard, self)
            end
          elsif 'reset' == l.strip
            # TODO work with 'bundle exec pry-remote-em ...'
            # TODO work with 'ruby -I lib bin/pry-remote-em ...'
            Kernel.puts "\033[1m#{$0} #{ARGV.join(' ')}\033[0m"
            exec("#{$0} #{ARGV.join(' ')}")
          else
            send_raw(l)
          end
        end

        EM.defer(operation, callback)
      end
    end # readline(prompt = @last_prompt)

    def add_to_history(line)
      if defined?(Readline) && @input == Readline
        Readline::HISTORY.push(line)
      end
      # Nothing to do with Coolline, it just works
    end
  end # module::Client
end # module::PryRemoteEm

# TODO detect if the old pager behavior of Pry is supported and use it. If it's not
# then don't bother adding a pager accessor
# Pry::Helpers::BaseHelpers#stagger_output expects Pry.pager to be defined
class Pry
  class << self
    attr_accessor :pager unless respond_to?(:pager)
  end
end
Pry.pager = true
