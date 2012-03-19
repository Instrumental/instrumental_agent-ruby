# Use the non -ffastthread Queue code from Ruby 1.8.7 to fix a
# bug in how REE handles GC with a thread from a forked
# parent process in the ext/thread/thread.c queue code.
module Instrumental
  class Queue
    #
    # Creates a new queue.
    #
    def initialize
      @que = []
      @waiting = []
      @que.taint    # enable tainted comunication
      @waiting.taint
      self.taint
    end

    #
    # Pushes +obj+ to the queue.
    #
    def push(obj)
      Thread.critical = true
      @que.push obj
      begin
        t = @waiting.shift
        t.wakeup if t
      rescue ThreadError
        retry
      ensure
        Thread.critical = false
      end
      begin
        t.run if t
      rescue ThreadError
      end
    end

    #
    # Alias of push
    #
    alias << push

    #
    # Alias of push
    #
    alias enq push

    #
    # Retrieves data from the queue.  If the queue is empty, the calling thread is
    # suspended until data is pushed onto the queue.  If +non_block+ is true, the
    # thread isn't suspended, and an exception is raised.
    #
    def pop(non_block=false)
      while (Thread.critical = true; @que.empty?)
        raise ThreadError, "queue empty" if non_block
        @waiting.push Thread.current
        Thread.stop
      end
      @que.shift
    ensure
      Thread.critical = false
    end

    #
    # Alias of pop
    #
    alias shift pop

    #
    # Alias of pop
    #
    alias deq pop

    #
    # Returns +true+ is the queue is empty.
    #
    def empty?
      @que.empty?
    end

    #
    # Removes all objects from the queue.
    #
    def clear
      @que.clear
    end

    #
    # Returns the length of the queue.
    #
    def length
      @que.length
    end

    #
    # Alias of length.
    #
    alias size length

    #
    # Returns the number of threads waiting on the queue.
    #
    def num_waiting
      @waiting.size
    end
  end
end