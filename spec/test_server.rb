require 'webrick'

class TestServer
  attr_accessor :host, :port, :connect_count, :commands, :connections

  def initialize(options={})
    default_options = {
      :listen => true,
      :authenticate => true,
      :response => true,
      :secure => false
    }
    @options = default_options.merge(options)

    @connect_count = 0
    @connections = []
    @commands = []
    @host = 'localhost'
    @main_thread = nil
    @server = nil
    listen if @options[:listen]
  end


  def listen
    @port ||= 10001
    @main_thread = Thread.new do
      @server = WEBrick::HTTPServer.new :Port => @port, :AccessLog => [], :Logger => Logger.new("/dev/null")
      @server.mount_proc "/report" do |req, res|
        @connect_count += 1
        @connections << [req["Authorization"], req["User-Agent"], req["X-Forwarded-For"]]
        if @options[:response]
          if @options[:authenticate]
            @commands << if req["Content-Encoding"] == "gzip"
              stream = StringIO.new(req.body)
              begin
                reader = Zlib::GzipReader.new(stream)
                content = reader.read
                JSON.parse(content)
              ensure
                reader.close
              end
            else
              JSON.parse(req.body)
            end
            res.status = "200"
            res.body = "OK"
          else
            res.status = "401"
            res.body = "GTFO"
          end
        else
          res.status = "0"
        end
      end
      @server.start
    end
  rescue Errno::EADDRINUSE => err
    puts "#{err.inspect} failed to get port #{@port}"
    puts err.message
    @port += 1
    retry
  end

  def protocol
    @options[:secure] ? "https" : "http"
  end

  def url
    "#{protocol}://#{host}:#{port}/report"
  end

  def stop
    @stopping = true
    @connect_count = 0
    @connections = []
    @commands = []
    @server.shutdown if @server
    @server = nil
    @main_thread.kill if @main_thread
    @main_thread = nil
    sleep(1)
  end

end
