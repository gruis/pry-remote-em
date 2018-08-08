module PryRemoteEm
  class Sandbox
    @@last_errors = []

    attr_accessor :pry

    %w[puts putc print p pp].each do |method|
      define_method method do |*arguments|
        pry.output.puts(*arguments)
      end
    end

    def inspect
      'sandbox'
    end

    def any_errors?
      @@last_errors.any?
    end

    def last_error
      @@last_errors.last
    end

    def self.add_error(exception, binding)
      unless exception.kind_of?(Exception) && exception.backtrace && binding.kind_of?(Binding)
        raise ArgumentError, 'exception with backtrace and binding expected'
      end

      exception.define_singleton_method(:binding) { binding }

      @@last_errors.push(exception)

      maximum_errors = ENV['PRYEMSANDBOXERRORS'].nil? || ENV['PRYEMSANDBOXERRORS'].empty? ? MAXIMUM_ERRORS_IN_SANDBOX : ENV['PRYEMSANDBOXERRORS'].to_i
      @@last_errors.shift if @@last_errors.size > maximum_errors
    end

    Pry.config.prompt_safe_objects.push(self)
  end
end