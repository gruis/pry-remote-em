module PryRemoteEm
  # See Readme for Sandbox using guide
  class Sandbox
    @@last_errors = []

    attr_accessor :pry, :server

    %w[puts putc print p pp].each do |method|
      define_method method do |*arguments|
        pry.output.puts(*arguments)
      end
    end

    def inspect
      'sandbox'
    end

    def any_errors?
      last_errors.any?
    end

    def last_error
      last_errors.last
    end

    def last_errors
      @@last_errors
    end

    def self.add_error(exception, source_binding = nil)
      unless exception.kind_of?(Exception) && exception.backtrace && (source_binding.nil? || source_binding.kind_of?(Binding))
        raise ArgumentError, 'exception with backtrace and optional binding expected'
      end

      return if @@last_errors.include?(exception)

      exception.define_singleton_method(:source_binding) { source_binding } if source_binding

      @@last_errors.push(exception)

      maximum_errors = ENV['PRYEMSANDBOXERRORS'].nil? || ENV['PRYEMSANDBOXERRORS'].empty? ? MAXIMUM_ERRORS_IN_SANDBOX : ENV['PRYEMSANDBOXERRORS'].to_i
      @@last_errors.shift if @@last_errors.size > maximum_errors
    end

    Pry.config.prompt_safe_objects.push(self)
  end
end