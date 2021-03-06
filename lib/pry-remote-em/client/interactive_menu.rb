require 'highline'

module PryRemoteEm
  module Client
    module InteractiveMenu
      def choose_server(list)
        highline    = HighLine.new
        choice      = nil
        url         = nil
        nm_col_len  = list.map { |id, server| server['name'].size }.max
        sc_col      = list.map { |id, server| second_column_for_server(server) }
        sc_col_name = opts[:show_details] == '@' ? 'details' : opts[:show_details] || 'url'
        sc_col_len  = [sc_col.flatten.map(&:size).max || 1, sc_col_name.size].max
        show_th_col = opts[:show_metrics] || list.any? { |id, server| server.has_key?('metrics') && server['metrics']['errors'] }
        if show_th_col
          th_col      = list.map { |id, server| third_column_for_server(server) }
          th_col_name = opts[:show_metrics] == '@' ? 'metrics' : opts[:show_metrics] || 'errors'
          th_col_len  = [th_col.flatten.map(&:size).max || 1, th_col_name.size].max
        end
        formatter   = "| %-3s |  %-#{nm_col_len}s  |  %-#{sc_col_len}s  |#{"  %-#{th_col_len}s  |" if show_th_col}"
        header      = sprintf(formatter, '', 'name', sc_col_name, *th_col_name)
        border      = ('-' * header.length)
        table       = [border, header, border]
        list        = list.to_a
        list        = filter_server_list(list)
        list        = sort_server_list(list)
        list.each.with_index do |(id, server), index|
          index_column = [(index + 1).to_s]
          first_column = [server['name']]
          second_column = second_column_for_server(server)
          third_column = third_column_for_server(server) if show_th_col

          lines = show_th_col ? [second_column.size, third_column.size].max : second_column.size

          lines.times do |index|
            table << sprintf(formatter, index_column[index] || '', first_column[index] || '', second_column[index] || '', *(show_th_col ? third_column[index] || '' : nil))
          end
        end
        table << border
        table = table.join("\n")
        Kernel.puts table

        proxy = if (choice = opts.delete(:proxy))
          true
        elsif (choice = opts.delete(:connect))
          false
        elsif opts.delete(:proxy_by_default)
          true
        else
          false
        end

        while url.nil?
          if proxy
            question = "(q) to quit; (r) to refresh; (c) to connect without proxy\nproxy to: "
          else
            question = "(q) to quit; (r) to refresh; (p) to proxy\nconnect to: "
          end

          choice = highline.ask(question)

          return close_connection if ['q', 'quit', 'exit'].include?(choice.downcase)
          if ['r', 'reload', 'refresh'].include?(choice.downcase)
            send_server_reload_list
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

          choice = choice[/^\d+$/] ?
            list[choice.to_i - 1] :
            list.detect { |(id, server)| choice == id || choice == server['name'] || server['urls'].include?(choice) }

          if choice
            id, server = *choice
            urls = filtered_urls_list_for_server(server)
            url = if urls.size > 1
              choose_url(urls)
            elsif urls.size == 1
              urls.first
            else
              log.error("\033[31mno #{'non-localhost ' if opts[:ignore_localhost]}urls for this server\033[0m")
              nil
            end
          else
            log.error("\033[31mserver not found\033[0m")
          end
        end

        return url, proxy
      end

      def choose_url(urls)
        highline = HighLine.new
        url      = nil
        length   = urls.map(&:size).max
        border   = '-' * (length + 8)
        Kernel.puts border
        urls.each.with_index do |url, index|
          Kernel.puts sprintf("| %d | %-#{length}s |", index + 1, url)
        end
        Kernel.puts border

        choice = highline.ask('select url: ')

        url = if choice && choice[/^\d+$/]
          urls[choice.to_i - 1]
        elsif urls.include?(choice)
          choice
        end

        log.error("\033[31mno url selected\033[0m") unless url

        return url
      end

      def sort_server_list(list)
        case opts[:sort]
        when :name
          list.sort { |(_, a), (_, b)| a['name'] <=> b['name'] }
        when :ssl
          list.sort &sort_by_uri(:scheme)
        when :port
          list.sort &sort_by_uri(:port)
        else # :host or default
          list.sort &sort_by_uri(:host)
        end
      end

      def sort_by_uri(part)
        -> a, b { URI.parse(a[1]['urls'].first).send(part) <=> URI.parse(b[1]['urls'].first).send(part) }
      end

      def filter_server_list(list)
        if opts[:filter_host]
          list = list.select { |(id, server)| server['urls'].any? { |url| URI.parse(url).host =~ opts[:filter_host] } }
        end
        if opts[:filter_name]
          list = list.select { |(id, server)| server['name'] =~ opts[:filter_name] }
        end
        if opts.has_key?(:filter_ssl)
          target_scheme = opts[:filter_ssl] ? 'pryems' : 'pryem'
          list = list.select { |(id, server)| server['urls'].any? { |url| URI.parse(url).scheme == target_scheme } }
        end
        if list.empty?
          log.info("\033[33m[pry-remote-em] no registered servers match the given filter\033[0m")
          Process.exit
        end
        list
      end

      def second_column_for_server(server)
        data = case opts[:show_details]
        when nil then filtered_urls_list_for_server(server)
        when '@' then server['details']
        else server['details'][opts[:show_details]]
        end

        prepare_data_for_table(data)
      end

      def filtered_urls_list_for_server(server)
        opts[:ignore_localhost] ? server['urls'].reject { |url| %w[localhost 127.0.0.1 ::1].include?(URI.parse(url).host) } : server['urls']
      end

      def third_column_for_server(server)
        data = case opts[:show_metrics]
        when nil then server['metrics']['errors']
        when '@' then server['metrics']
        else server['metrics'][opts[:show_metrics]]
        end

        prepare_data_for_table(data)
      end

      def prepare_data_for_table(data)
        case data
        when Array then data.map(&:to_s)
        when Hash then data.map { |key, value| "#{key}: #{value}" }
        else [data.to_s]
        end
      end
    end # module::InteractiveMenu
  end # module::Client
end # module PryRemoteEm
