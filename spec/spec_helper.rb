$: << File.join(File.dirname(__FILE__), "..", "lib")

require 'instrumental_agent'
require 'test_server'

RSpec.configure do |config|

  config.before(:all) do
    unless EM.reactor_running?
      EM.error_handler { |*args| 
        puts "\n"
        puts "*" * 80
        puts "EVENTMACHINE ERROR: #{args.inspect}\n" 
        puts args.first.backtrace.join("\n")
        puts "*" * 80
        puts "\n"
      }
      Thread.new { EM.run }
      sleep(0.001) while !EM.reactor_running?
    end
  end

  config.after(:all) do
  end

end


module EM

  def self.next(&block)
    EM.wait_for_events
    mtx = Mutex.new
    exc = nil
    EM.next_tick do
      mtx.synchronize {
        begin
          yield
        rescue Exception => e
          exc = e
        end
      }
    end
    EM.wait_for_events
    mtx.lock
    raise exc if exc
    true
  end

  def self.wait_for_events
    raise "Reactor is not running" unless EM.reactor_running?
    while EM.reactor_running? && !(@next_tick_queue && @next_tick_queue.empty? && @timers && @timers.empty?)
      sleep(0.01) # This value is REALLY important
                  # Too low and it doesn't allow 
                  # local socket events to finish 
                  # processing
                  # Too high and it makes the tests 
                  # slow.  
    end
    raise @wrapped_exception if @wrapped_exception
  end
end