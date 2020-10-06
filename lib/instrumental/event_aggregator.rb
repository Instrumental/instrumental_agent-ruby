class EventAggregator
  attr_accessor :counts, :values, :received_at, :frequency
 
  METRIC_TYPES = ["increment".freeze, "gauge".freeze].freeze

  def initialize(options = {})
    @values = Hash.new
    @frequency = options[:frequency] || Instrumental::Agent::DEFAULT_FREQUENCY
  end

  def put(command)
    command_at = command.time
    unless(command_at % frequency == 0)
      command.time = (command_at - (command_at % frequency)).to_i
    end
    metadata = command.metadata
    @values[metadata] = (command + @values[metadata])
  end

  def each
    return enum_for(:each) unless block_given?
    @values.each do |(type, metric, time, project_id), (value, count)|
      yield(type, metric, value, count, time, project_id, @received_at)
    end
  end

  def size
    @values.size
  end

  def coerce_time(time)
    itime = time.to_i
    (itime - (itime % frequency)).to_i
  end
end
