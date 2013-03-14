require 'logger'
require 'openssl'
require 'webrick'
require 'webrick/https'

# TODO: With the switch to Net::HTTP, the need for TestServer
# could be obviated mostly by Webmock. Investigate.
class TestServer
  attr_accessor :host, :port, :connect_count, :commands, :connections

  def self.next_port
    @port ||= 10001
    @port += 1
  end

  def initialize(options={})
    default_options = {
      :listen => true,
      :authenticate => true,
      :response => true,
      :secure => false,
      :certificate => nil,
      :private_key => nil
    }
    @options = default_options.merge(options)

    @connect_count = 0
    @connections = []
    @commands = []
    @host = 'localhost'
    @main_thread = nil
    @server = nil
    if @options[:certificate] && @options[:private_key]
      @certificate = OpenSSL::X509::Certificate.new(File.read(@options[:certificate]))
      @private_key = OpenSSL::PKey::RSA.new(File.read(@options[:private_key]))
    end
    listen if @options[:listen]
  end


  def listen
    @port = TestServer.next_port
    @main_thread = Thread.new do
      begin
        options = { :Port => @port, :AccessLog => [], :Logger => Logger.new("/dev/null") }
        if @certificate && @private_key
          options[:SSLEnable] = true
          options[:SSLCertificate] = @certificate
          options[:SSLPrivateKey] = @private_key
        end
        @server = WEBrick::HTTPServer.new options
        @server.mount_proc "/report" do |req, res|
          begin
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
          rescue Exception => e
            puts e.message
          end
        end
        @server.start
      rescue Errno::EADDRINUSE => err
        puts "#{err.inspect} failed to get port #{@port}"
        puts err.message
        retry
      rescue Exception => e
        puts "%s\n%s" % [e.message, e.backtrace.join("\n")]
        puts "Tests will fail due to server startup failing"
        raise
      end
    end
    sleep(0.1) while (@server.nil? || @server.listeners.empty?)
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
    @main_thread.kill if @main_thread
    @main_thread = nil
    sleep(1)
    @server.shutdown if @server
    @server = nil
  end

end
