# Prefer MessagePack "out of the box" protocol over old JSON+Zlib+CRC
# variant because of strange `expected "PRYEM" not "}PRYE"` errors
# on long output over network (not localhost).
require 'msgpack'

module PryRemoteEm
  module Proto
    def receive_data(data)
      @unpacker ||= MessagePack::Unpacker.new
      @unpacker.feed_each(data) { |object| receive_object(object) }
    end

    def send_object(object)
      send_data(object.to_msgpack)
    end

    def receive_object(j)
      if !j.is_a?(Hash)
        receive_unknown(j)
      elsif j['p']
        receive_prompt(j['p'])
      elsif j['d']
        receive_raw(j['d'])
      elsif j['m']
        receive_msg(j['m'])
      elsif j['mb']
        receive_msg_bcast(j['mb'])
      elsif j['s']
        receive_shell_cmd(j['s'])
      elsif j.include?('sc')
        receive_shell_result(j['sc'])
      elsif j['g']
        receive_banner(*j['g'].split(' ', 3))
      elsif j['c']
        receive_completion(j['c'])
      elsif j['cb']
        receive_clear_buffer
      elsif j.include?('a')
        receive_auth(*Array(j['a']))
      elsif j['sd']
        receive_shell_data(j['sd'])
      elsif j['ssc']
        receive_shell_sig(j['ssc'].to_sym)
      elsif j['hb']
        receive_heartbeat(j['hb'])
      elsif j['rs']
        receive_register_server(*Array(j['rs']))
      elsif j['urs']
        receive_unregister_server(j['urs'])
      elsif j['sl']
        receive_server_list(j['sl'])
      elsif j['srl']
        receive_server_reload_list
      elsif j['tls']
        receive_start_tls
      elsif j['pc']
        receive_proxy_connection(j['pc'])
      else
        receive_unknown(j)
      end
    end


    def receive_prompt(p); end
    def receive_banner(name, version, scheme); end
    def receive_auth(a, b = nil); end
    def receive_msg(m); end
    def receive_msg_bcast(mb); end
    def receive_shell_cmd(c); end
    def receive_shell_result(c); end
    def receive_shell_sig(sym); end
    def receive_shell_data(d); end
    def receive_completion(c); end
    def receive_clear_buffer; end
    def receive_raw(r); end
    def receive_unknown(j); end

    def receive_start_tls; end

    def receive_register_server(id, urls, name, details, metrics); end
    def receive_unregister_server(id); end
    def receive_server_list(list); end
    def receive_server_reload_list; end

    def receive_proxy_connection(url); end

    def send_banner(g)
      send_object({g: g})
    end
    def send_auth(a)
      send_object({a: a})
    end
    def send_prompt(p)
      send_object({p: p})
    end
    def send_msg_bcast(m)
      send_object({mb: m})
    end
    def send_msg(m)
      send_object({m: m})
    end
    def send_shell_cmd(c)
      send_object({s: c})
    end
    def send_shell_result(r)
      send_object({sc: r})
    end
    def send_shell_sig(sym)
      send_object({ssc: sym})
    end
    def send_shell_data(d)
      send_object({sd: d})
    end
    def send_completion(word)
      send_object({c: word})
    end
    def send_clear_buffer
      send_object({cb: true})
    end
    def send_raw(d)
      send_object(d.is_a?(String) ? {d: d} : d)
    end

    def send_start_tls
      send_object({tls: true})
    end

    def send_register_server(id, urls, name, details, metrics)
      send_object({rs: [id, urls, name, details, metrics]})
    end
    def send_unregister_server(id)
      send_object({urs: id})
    end
    def send_heatbeat(url)
      send_object({hb: url})
    end
    def send_server_list(list = nil)
      send_object({sl: list})
    end
    def send_server_reload_list
      send_object({srl: true})
    end

    def send_proxy_connection(url)
      send_object({pc: url})
    end
  end # module::Proto
end # module::PryRemoteEm
