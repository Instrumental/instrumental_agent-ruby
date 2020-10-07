class EventAggregator
  attr_accessor :counts, :values, :received_at, :frequency
 
  def initialize(options = {})
    @values = Hash.new
    @frequency = options[:frequency] || Instrumental::Agent::DEFAULT_FREQUENCY
  end

  def put(command)
    command_at = command.time
    unless(command_at % frequency == 0)
      command.time = (command_at - (command_at % frequency))
    end
    metadata = command.metadata
    @values[metadata] = (command + @values[metadata])
  end

  def size
    @values.size
  end

  def coerce_time(time)
    itime = time.to_i
    (itime - (itime % frequency)).to_i
  end
end
