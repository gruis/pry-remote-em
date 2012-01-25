require 'json'

module PryRemoteEm
  module JsonProto
    DELIM     = ']]>]]><[[<[['

    def receive_data(d)
      return unless d && d.length > 0
      @buffer ||= "" # inlieu of a post_init

      if six = d.index(DELIM)
        @buffer << d[0...six]
        j = JSON.load(@buffer)
        @buffer.clear
        receive_json(j)
        receive_data(d[(six + DELIM.length)..-1])
      else
        @buffer << d
      end
    end

    def receive_json(j)
    end

    def send_data(d)
      super(JSON.dump(d.is_a?(String) ? {:d => d} : d) + DELIM)
    end

  end # module::JsonProto
end # module::PryRemoteEm
