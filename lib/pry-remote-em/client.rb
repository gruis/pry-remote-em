require 'uri'
require 'pry-remote-em'
require 'pry-remote-em/client/keyboard'
require "pry-remote-em/client/generic"
require 'pry/helpers/base_helpers'
#require "readline"   # doesn't work with Fiber.yield
        #  - /Users/caleb/src/pry-remote-em/lib/pry-remote-em/client.rb:45:in `yield': fiber called across stack rewinding barrier (FiberError)
require "rb-readline" # doesn't provide vi-mode support :(
        # https://github.com/luislavena/rb-readline/issues/21
        # https://github.com/simulacre/rb-readline/commit/0376eb4e9526b3dc1a6512716322efcef409628d
require 'highline'

module PryRemoteEm
  module Client
    include EM::Deferrable
    include Client::Generic
    include Pry::Helpers::BaseHelpers

    class << self
      def start(host = PryRemoteEm::DEFHOST, port = PryRemoteEM::DEFPORT, opts = {:tls => false})
        EM.connect(host || PryRemoteEm::DEFHOST, port || PryRemoteEm::DEFPORT, PryRemoteEm::Client, opts) do |c|
          c.callback { yield if block_given? }
          c.errback do |e|
            Kernel.puts "[pry-remote-em] connection failed\n#{e}"
            yield(e) if block_given?
          end
        end
      end
    end # class << self

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
      Readline.completion_proc = method(:auto_complete)
    end

    def ssl_handshake_completed
      log.info("[pry-remote-em] TLS connection established")
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
        log.info("[pry-remote-em] session terminated")
        # prior to 1.0.0.b4 error? returns true here even when it's not
        return succeed if Gem.loaded_specs["eventmachine"].version < Gem::Version.new("1.0.0.beta4")
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
      choice, proxy  = choose_server(list)
      return unless choice
      uri, name      = URI.parse(choice[0]), choice[1]
      if proxy
        @opts[:tls]  = uri.scheme == 'pryems'
        @negotiated  = false
        @tls_started = false
        return send_proxy_connection(uri)
      end
      @reconnect_to = uri
      close_connection
    end

    def choose_server(list)
      highline    = HighLine.new
      proxy       = false
      choice      = nil
      nm_col_len  = list.values.map(&:length).sort[-1] + 5
      ur_col_len  = list.keys.map(&:length).sort[-1] + 5
      header      = sprintf("| %-3s |  %-#{nm_col_len}s |  %-#{ur_col_len}s |", "id", "name", "url")
      border      = ("-" * header.length)
      table       = [border, header, border]
      list        = list.to_a
      list.each_with_index do |(url, name), idx|
        table << sprintf("|  %-2d |  %-#{nm_col_len}s |  %-#{ur_col_len}s |", idx + 1, name, url)
      end
      table << border
      table   = table.join("\n")
      Kernel.puts table
      while choice.nil?
        if proxy
          question = "(q) to quit; (r) to refresh (c) to connect\nproxy to: "
        else
          question = "(q) to quit; (r) to refresh (p) to proxy\nconnect to: "
        end
        choice = highline.ask(question)
        return close_connection if ['q', 'quit', 'exit'].include?(choice.downcase)
        if ['r', 'reload', 'refresh'].include?(choice.downcase)
          send_server_list
          return nil
        end
        if ['c', 'connect'].include?(choice.downcase)
          proxy = false
          choice = nil
          next
        end
        if ['p', 'proxy'].include?(choice.downcase)
          proxy = true
          choice = nil
          next
        end
        choice = choice.to_i.to_s == choice ?
          list[choice.to_i - 1] :
          list.find{|(url, name)| url == choice || name == choice }
      end
      [choice, proxy]
    end

    def receive_prompt(p)
      readline(p)
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
    end

    def receive_completion(c)
      @waiting, f = nil, @waiting
      f.resume(c) if f
    end

    def receive_raw(r)
      # Pry::Helpers::BaseHelpers
      stagger_output(r, $stdout)
    end

    def receive_unknown(j)
      warn "[pry-remote-em] received unexpected data: #{j.inspect}"
    end

    def auto_complete(word)
      @waiting = Fiber.current
      send_completion(word)
      return Fiber.yield
    end

    def authenticate
      return fail("[pry-remote-em] authentication required") unless @auth
      return fail("[pry-remote-em] can't authenticate before negotiation complete") unless @negotiated
      user, pass = @auth.call
      return fail("[pry-remote-em] expected #{@auth} to return a user and password") unless user && pass
      send_auth([user, pass])
    end # authenticate

    def readline(prompt)
      if @negotiated && !@unbound
        Fiber.new {
          l = Readline.readline(prompt, !prompt.nil?)
          if '!!' == l[0..1]
            send_msg_bcast(l[2..-1])
          elsif '!' == l[0]
            send_msg(l[1..-1])
          elsif '.' == l[0]
            send_shell_cmd(l[1..-1])
            if Gem.loaded_specs["eventmachine"].version < Gem::Version.new("1.0.0.beta4")
              Kernel.puts "\033[1minteractive shell commands are not well supported when running on EventMachine prior 1.0.0.beta4\033[0m"
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
          end # "!!" == l[0..1]
        }.resume
      end
    end # readline(prompt = @last_prompt)

  end # module::Client
end # module::PryRemoteEm

# Pry::Helpers::BaseHelpers#stagger_output expects Pry.pager to be defined
class Pry
  class << self
    attr_accessor :pager unless respond_to?(:pager)
  end
end
Pry.pager = true
