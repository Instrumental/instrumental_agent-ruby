require 'spec_helper'

describe MetricBuffer do
  it "should know its start time" do
    ta = MetricBuffer.new(1)
    ta.start_time.should == 1
  end

  it "should batch multiple increments into one by addition" do
    ta = MetricBuffer.new(1)
    ta.increment('abc', 2)
    ta.increment('abc', 3)
    ta.increments['abc'].should == 5
  end

  it "should batch multiple gauges into one by using the last value" do
    ta = MetricBuffer.new(1)
    ta.gauge('abc', 2)
    ta.gauge('abc', 3)
    ta.gauges['abc'].should == 3
  end
end