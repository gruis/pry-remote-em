module PryRemoteEm
  # Simple metrics system
  # See Sandbox section in Readme for guide
  module Metrics
    def list
      @list ||= Hash.new { |hash, key| hash[key] = 0 }
    end

    def add(name, value = 1)
      list[name] += value
    end

    def reduce(name, value = 1)
      add(name, -value)
    end

    def maximum(name, value)
      list[name] = value if list[name] < value
    end

    def minimum(name, value)
      list[name] = value if list[name] > value
    end

    def set(name, value)
      list[name] = value
    end

    def get(name)
      list[name]
    end

    def any?
      list.any?
    end

    extend self
  end
end