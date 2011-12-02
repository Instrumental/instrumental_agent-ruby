require 'spec_helper'

describe MetricBufferPool do
  it "should create a buffer for the quantized time for increments" do
    mbp = MetricBufferPool.new(60, 3)
    now = Time.now.to_i
    mbp.increment('abc', 1, now)
    mbp.buffers[(now / 60).floor * 60].increments['abc'].should == 1
  end

  it "should create a buffer for the quantized time for gauges" do
    mbp = MetricBufferPool.new(60, 3)
    now = Time.now.to_i
    mbp.gauge('abc', 2, now)
    mbp.buffers[(now / 60).floor * 60].increments['abc'].should_not == 2
    mbp.buffers[(now / 60).floor * 60].gauges['abc'].should == 2
  end

  it "should reuse the buffer with repeated times" do
    mbp = MetricBufferPool.new(60, 3)
    now = Time.now.to_i
    mbp.increment('abc', 1, now)
    mbp.increment('abc', 2, now)
    mbp.buffers[(now / 60).floor * 60].increments['abc'].should == 3
  end

  it "should use different buffers when times differ by more than resolution" do
    mbp = MetricBufferPool.new(60, 3)
    now = Time.now.to_i
    mbp.increment('abc', 1, now)
    mbp.increment('abc', 2, now - 60)
    mbp.buffers[(now / 60).floor * 60].increments['abc'].should == 1
    mbp.buffers[((now - 60)/ 60).floor * 60].increments['abc'].should == 2
  end
end

describe MetricBufferPool, "eviction" do
  before(:each) do
    @evicted = []
    @callback = proc { |buffer| evicted << evicted }
  end

  it "should evict the least recently used buffer" do
    mbp = MetricBufferPool.new(1, 3, &@callback)
    mbp.increment('abc', 1, 1)
    mbp.increment('abc', 2, 2)
    @callback.should_receive(:call).once.with do |buffer|
      buffer.increments['abc'].should == 1
    end
    mbp.evict_least_recently_used_buffer.should == true
  end

  it "should be safe to evict without a callback" do
    mbp = MetricBufferPool.new(1, 3)
    mbp.increment('abc', 1, 1)
    mbp.evict_least_recently_used_buffer.should == true
  end

  it "should be safe to evict more times than there are buffers" do
    mbp = MetricBufferPool.new(1, 3)
    mbp.increment('abc', 1, 1)
    mbp.increment('abc', 2, 2)
    mbp.stub!(:eviction)
    mbp.evict_least_recently_used_buffer.should == true
    mbp.evict_least_recently_used_buffer.should == true
    mbp.evict_least_recently_used_buffer.should == nil
  end

  it "should automatically evict when pool is larger than max_size" do
    mbp = MetricBufferPool.new(1, 3, &@callback)
    mbp.increment('abc', 1, 1)
    mbp.increment('abc', 2, 2)
    mbp.increment('abc', 3, 3)
    @callback.should_receive(:call).once.with do |buffer|
      buffer.increments['abc'].should == 1
    end
    mbp.increment('abc', 4, 4)
  end

  it "should evict all buffers" do
    mbp = MetricBufferPool.new(1, 3, &@callback)
    mbp.increment('abc', 1, 1)
    mbp.increment('abc', 2, 2)
    mbp.increment('abc', 3, 3)
    @callback.should_receive(:call).exactly(3).times
    mbp.evict_all_buffers
  end

end
