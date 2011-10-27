module TestServer
  CMUTEX = Mutex.new

  def self.start_reactor
    Thread.new { EM.run } unless EM.reactor_running?
  end

  def self.start(port)
    start_reactor
    unless @sig
      EM.next_tick {
        @sig = EventMachine.start_server "127.0.0.1", port, TestServer
      }
    end
  end

  def self.stop
    if (sig=@sig)
      EM.next_tick {
        EventMachine.stop_server sig
      }
      @sig = nil
    end
  end

  def self.connections
    CMUTEX.synchronize do 
      @connections ||= []
      @connections.dup
    end
  end

  def self.add_connection(conn)
    CMUTEX.synchronize do
      @connections ||= []
      @connections << conn
    end
  end

  def self.remove_connection(conn)
    CMUTEX.synchronize do
      @connections ||= []
      @connections.delete(conn)
    end
  end

  def self.last
    connections.last
  end

  def post_init
    TestServer.add_connection(self)
  end

  def receive_data data
    buffer_response(data)
  end

  def unbind
    TestServer.remove_connection(self)
  end

  def last_message
    buffer.last
  end

  def buffer
    @buffer ||= []
    @buffer.dup
  end

  def clear_buffer!
    @buffer = []
  end

  def buffer_response(dt)
    @buffer ||= []
    dt.split(/\n/).each do |measurement|
      @buffer << measurement
    end
    dt
  end
end


