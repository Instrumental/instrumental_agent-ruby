module Instrumental
  class MetricBuffer
    attr_reader :increments, :gauges, :last_used_at, :start_time

    def initialize(start_time)
      @start_time = start_time
      @increments = Hash.new(0)
      @gauges = {}
    end

    def increment(key, value)
      used!
      @increments[key] += value
    end

    def gauge(key, value)
      used!
      @gauges[key] = value
    end

    def used!
      @last_used_at = Time.now
    end

    def <=>(other)
      @last_used_at <=> other.last_used_at
    end

  end
end