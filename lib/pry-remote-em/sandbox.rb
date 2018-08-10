require 'pry-remote-em/metrics'

module PryRemoteEm
  # See Readme for Sandbox using guide
  class Sandbox
    attr_accessor :pry, :server

    # Use output methods as expected

    %w[puts putc print p pp].each do |method|
      define_method method do |*arguments|
        pry.output.puts(*arguments)
      end
    end

    # Working with errors

    @@last_errors = []
    @@ignore_errors = []
    @@error_classes = Hash.new { |hash, key| hash[key] = 0 }

    def error_classes
      return puts 'No errors, yay!' if @@error_classes.empty?
      puts @@error_classes.map { |key, value| "#{key}: #{value}" }
    end

    def error_history
      return puts 'No errors, yay!' unless any_errors?
      puts @@last_errors.map { |error| "#{error.source_timestamp} #{"#{error.class}: #{error.message}".sub(/(?<=^.{51}).{4,}$/, '...')}" }
    end

    def self.add_error(exception, source_binding = nil)
      unless exception.kind_of?(Exception) && exception.backtrace && (source_binding.nil? || source_binding.kind_of?(Binding))
        raise ArgumentError, 'exception with backtrace and optional binding expected'
      end

      return if @@last_errors.map(&:object_id).include?(exception.object_id) || @@ignore_errors.include?(exception.class)

      timestamp = Time.now
      exception.define_singleton_method(:source_timestamp) { timestamp }

      exception.define_singleton_method(:source_binding) { source_binding } if source_binding

      @@last_errors.push(exception)
      @@error_classes[exception.class] += 1
      Metrics.add(:errors)

      maximum_errors = ENV['PRYEMSANDBOXERRORS'].nil? || ENV['PRYEMSANDBOXERRORS'].empty? ? MAXIMUM_ERRORS_IN_SANDBOX : ENV['PRYEMSANDBOXERRORS'].to_i
      @@last_errors.shift if @@last_errors.size > maximum_errors
    end

    def self.last_errors
      @@last_errors
    end

    def self.any_errors?
      @@last_errors.any?
    end

    def self.last_error
      @@last_errors.last
    end

    def self.ignore_errors
      @@ignore_errors
    end

    %w[any_errors? last_errors last_error ignore_errors].each do |method|
      define_method(method) do |*arguments|
        self.class.send(method, *arguments)
      end
    end

    # Metrics related methods

    def show_metrics
      puts Metrics.list.map { |key, value| "#{key}: #{value}" }
    end

    # Safely show in Pry prompt

    def inspect
      'sandbox'
    end

    Pry.config.prompt_safe_objects.push(self)
  end
end