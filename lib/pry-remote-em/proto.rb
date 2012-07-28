require 'json'
require "zlib"

module PryRemoteEm
  module Proto
    PREAMBLE      = 'PRYEM'
    SEPERATOR     = ' '
    PREAMBLE_LEN  = PREAMBLE.length
    SEPERATOR_LEN = SEPERATOR.length

    def send_json(d)
      send_data(JSON.dump(d.is_a?(String) ? {:d => d} : d))
    end

    def send_data(data)
      crc  = Zlib::crc32(data).to_s
      msg  = PREAMBLE + (data.length + crc.length + SEPERATOR_LEN).to_s + SEPERATOR + crc + SEPERATOR +  data
      super(msg)
    end

    # Each frame is a string consisting of 4 parts
    #   1. preamble (PRYEM)
    #   2. length in characters of crc, a seperator, and body
    #   3. CRC
    #   4. JSON encoded body
    # It is possible and likely that receive_data will be given more than one frame at a time, or
    # an incomplete frame.
    # @example "PRYEM42 3900082256 {\"g\":\"PryRemoteEm 0.7.0 pryem\"}PRYEM22 1794245389 {\"a\":false}"
    def receive_data(d)
      return unless d && d.length > 0
      @buffer ||= "" # inlieu of a post_init
      @buffer << d
      while @buffer && !@buffer.empty?
        return unless @buffer.length >= PREAMBLE_LEN &&
          (len_ends = @buffer.index(SEPERATOR)) &&
          (crc_ends = @buffer.index(SEPERATOR, len_ends))
        if (preamble = @buffer[0...PREAMBLE_LEN]) != PREAMBLE
          raise "message is not in proper format; expected #{PREAMBLE.inspect} not #{preamble.inspect}"
        end
        length    = @buffer[PREAMBLE_LEN ... len_ends].to_i
        return if len_ends + length > @buffer.length
        crc_start = len_ends + SEPERATOR_LEN
        crc, data = @buffer[crc_start ... crc_start + length].split(SEPERATOR, 2)
        crc       = crc.to_i
        @buffer   = @buffer[crc_start + length .. -1]
        if (dcrc = Zlib::crc32(data)) == crc
          receive_json(JSON.load(data))
        else
          warn("data crc #{dcrc} doesn't match crc #{crc.inspect}; discarding #{data.inspect}")
        end
      end
      @buffer
    end

    def receive_json(j)
      if j['p']
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
        receive_banner(*j['g'].split(" ", 3))
      elsif j['c']
        receive_completion(j['c'])
      elsif j.include?('a')
        receive_auth(*Array(j['a']))
      elsif j['sd']
        receive_shell_data(j['sd'])
      elsif j['ssc']
        receive_shell_sig(:term)
      elsif j['hb']
        receive_heartbeat(j['hb'])
      elsif j['rs']
        receive_register_server(*Array(j['rs']))
      elsif j['urs']
        receive_unregister_server(j['urs'])
      elsif j.include?('sl')
        j['sl'] ?  receive_server_list(j['sl']) : receive_server_list
      elsif j['tls']
        receive_start_tls
      elsif j['pc']
        receive_proxy_connection(j['pc'])
       elsif j['e']
         receive_edit(*j['e'])
       elsif j['ec']
         receive_edit_changed(*j['ec'])
       elsif j['ef']
         receive_edit_failed(*j['ef'])
      else
        receive_unknown(j)
      end
      j
    end


    def receive_prompt(p); end
    def receive_banner(name, version, scheme); end
    def receive_auth(a, b = nil); end
    def receive_msg(m); end
    def receive_msg_bcast(mb); end
    def receive_shell_cmd(c); end
    def receive_shell_result(c); end
    def receive_completion(c); end
    def receive_raw(r); end
    def receive_shell_sig(sym); end
    def receive_shell_data(d); end
    def receive_unknown(j); end

    def receive_start_tls; end

    def receive_register_server(url, name); end
    def receive_unregister_server(url); end
    def receive_server_list(list = nil); end

    def receive_proxy_connection(url); end

    def recieve_edit(file, line, contents); end
    def receive_edit_changed(file, line_yes_no, diff = ""); end
    def receive_edit_failed(file, line, error); end


    def send_banner(g)
      send_json({:g => g})
    end
    def send_auth(a)
      send_json({:a => a})
    end
    def send_prompt(p)
      send_json({:p => p})
    end
    def send_msg_bcast(m)
      send_json({:mb => m})
    end
    def send_msg(m)
      send_json({:m => m})
    end
    def send_shell_cmd(c)
      send_json({:s => c})
    end
    def send_shell_result(r)
      send_json({:sc => r})
    end
    def send_completion(word)
      send_json({:c => word})
    end
    def send_raw(l)
      send_json(l)
    end

    def send_start_tls
      send_json({:tls => true})
    end

    def send_register_server(url, name)
      send_json({:rs => [url, name]})
    end
    def send_unregister_server(url)
      send_json({:urs => url})
    end
    def send_heatbeat(url)
      send_json({:hb => url})
    end
    def send_server_list(list = nil)
      send_json({:sl => list})
    end

    def send_proxy_connection(url)
      send_json({:pc => url})
    end

    def send_edit(file, line, contents)
      send_json({:e => [file, line, contents]})
    end

    def send_edit_changed(file, line_yes_no, diff = nil)
      send_json({:ec => [file, line_yes_no, diff].compact})
    end
    def send_edit_failed(file, line, error)
      send_json({:ef => [file, line, error]})
    end
  end # module::Proto
end # module::PryRemoteEm
