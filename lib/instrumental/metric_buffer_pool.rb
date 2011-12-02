module Instrumental
  class MetricBufferPool
    attr_reader :buffers, :max_size

    def initialize(resolution, max_size, &eviction_callback)
      @resolution = resolution.to_i
      @max_size = max_size
      @buffers = {}
      @eviction_callback = eviction_callback
    end

    def increment(key, value, time)
      buffer_for_time(time).increment(key, value)
    end

    def gauge(key, value, time)
      buffer_for_time(time).gauge(key, value)
    end

    def buffer_for_time(time)
      time_key = quantize_time(time)
      buffer = @buffers[time_key]
      if !buffer
        if buffers.size + 1 > max_size
          evict_least_recently_used_buffer
        end
        buffer = @buffers[time_key] = MetricBuffer.new(time_key)
      end
      buffer
    end

    def quantize_time(time)
      time / @resolution * @resolution
    end

    def evict_least_recently_used_buffer
      if !buffers.empty?
        stale_buffer = buffers.values.sort.first
        buffers.delete(stale_buffer.start_time)
        @eviction_callback && @eviction_callback.call(stale_buffer)
        true
      end
    end

    def evict_all_buffers
      loop do
        break if !evict_least_recently_used_buffer
      end
    end

  end
end