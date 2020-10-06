module Instrumental
  METRIC_TYPES = ["increment".freeze, "gauge".freeze].freeze
  
  Command = Struct.new(:command, :metric, :value, :time, :count) do
    def initialize(*args)
      super(*args)
      self.time = time.to_i
    end
    
    def to_s
      [command, metric, value, time, count].map(&:to_s).join(" ")
    end

    def metadata
      "#{metric}:#{time}".freeze
    end

    def +(other_command)
      return self if other_command.nil?
      raise ArgumentError.new("Commands can only be added to other commands") unless other_command.is_a?(Command)

      unless metadata == other_command.metadata
        raise ArgumentError.new("Commands must have matching command, metric, and time to be added together")
      end

      Command.new(command, metric, value + other_command.value, time, count + other_command.count)
    end
  end

  Notice = Struct.new(:note, :time, :duration) do
    def to_s
      ["notice".freeze, time, duration, note].map(&:to_s).join(" ")
    end
  end
end
