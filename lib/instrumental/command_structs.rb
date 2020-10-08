module Instrumental
  METRIC_TYPES = ["increment".freeze, "gauge".freeze].freeze

  Command = Struct.new(:command, :metric, :value, :time, :count) do
    def initialize(command, metric, value, time, count)
      super(command, metric, value, time.to_i, count.to_i)
    end

    def to_s
      [command, metric, value, time, count].map(&:to_s).join(" ")
    end

    def metadata
      "#{metric}:#{time}".freeze
    end

    def +(other_command)
      return self if other_command.nil?
      Command.new(command, metric, value + other_command.value, time, count + other_command.count)
    end
  end

  Notice = Struct.new(:note, :time, :duration) do
    def initialize(note, time, duration)
      super(note, time.to_i, duration.to_i)
    end

    def to_s
      ["notice".freeze, time, duration, note].map(&:to_s).join(" ")
    end
  end
end
