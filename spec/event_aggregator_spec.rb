require 'spec_helper'

describe Instrumental::Command, "basic functions of command structs" do
  it "should not allow bad arguments to command#+" do
    command = Instrumental::Command.new("gauge", "abc", 1, Time.at(0), 1)

    # not a command
    expect { command + "random_stuff" }.to raise_error(ArgumentError)
    # different metric
    expect { command + Instrumental::Command.new("gauge", "xyz", 1, Time.at(0), 1) }.to raise_error(ArgumentError)
    # different time
    expect { command + Instrumental::Command.new("gauge", "xyz", 1, Time.at(999), 1) }.to raise_error(ArgumentError)    
    # nil is a no-op
    expect(command + nil).to eq(command)
    # it will change the top of the other command
    expect(command + Instrumental::Command.new("increment", "abc", 1, Time.at(0), 1))
      .to eq(Instrumental::Command.new("gauge", "abc", 2, Time.at(0), 2))
  end

  it "should add together with like commands" do
    command = Instrumental::Command.new("gauge", "abc", 1, Time.at(0), 1)
    other   = Instrumental::Command.new("gauge", "abc", 2, Time.at(0), 4)
    expect(command + other).to eq(Instrumental::Command.new("gauge", "abc", 3, Time.at(0), 5))
  end
end

describe EventAggregator, "time and frequency operations" do
  it "should massage time values to match the start of a window" do
    agg = EventAggregator.new(frequency: 10)
    Timecop.freeze do
      start_of_minute = Time.now.to_i - (Time.now.to_i % 60)
      times_to_report = [start_of_minute + 5, start_of_minute + 15]
      
      times_to_report.each do |at_time|
        agg.put(Instrumental::Command.new("gauge", "abc", 5, Time.at(at_time), 1))
      end

      expect(agg.size).to eq(2)

      expected_values = [Instrumental::Command.new("gauge", "abc", 5, Time.at(start_of_minute), 1),
                         Instrumental::Command.new("gauge", "abc", 5, Time.at(start_of_minute + 10), 1)]
      expect(agg.values.values).to eq(expected_values)
    end
  end
end

describe EventAggregator do
  it "should aggregate put operations to a given frequency" do
    start_of_minute = Time.now.to_i - (Time.now.to_i % 60)
    Timecop.freeze(Time.at(start_of_minute)) do
      agg = EventAggregator.new(frequency: 30)
      (Time.now.to_i..(Time.now.to_i + 119)).each do |time|
        agg.put(Instrumental::Command.new("increment", "abc", 1, time, 1))
      end
      expect(agg.size).to eq(4)
      (Time.now.to_i..(Time.now.to_i + 119)).step(30).map do |time|
        expect(agg.values["abc:#{time}"]).to eq(Instrumental::Command.new("increment", "abc", 30, time, 30))
      end
    end
  end

  it "should aggregate put operations to the same metric and last type wins" do
    Timecop.freeze do
      agg = EventAggregator.new

      agg.put(Instrumental::Command.new("gauge", "hello", 3.0, Time.now, 1))
      agg.put(Instrumental::Command.new("increment", "hello", 4.0, Time.now, 1))
      
      expect(agg.size).to eq(1)
      expect(agg.values.values.first).to eq(Instrumental::Command.new("increment",
                                                                     "hello",
                                                                     7.0,
                                                                     agg.coerce_time(Time.now),
                                                                     2))
    end
  end
end
