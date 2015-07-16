require 'openssl'

class TestServer
  attr_accessor :host, :port, :connect_count, :commands

  def initialize(options={})
    default_options = {
      :listen => true,
      :authenticate => true,
      :response => true,
      :secure => false
    }
    @options = default_options.merge(options)

    dir = File.expand_path(File.dirname(__FILE__))
    @certificate = OpenSSL::X509::Certificate.new(File.open(File.join(dir, "test.crt")))
    @key = OpenSSL::PKey::RSA.new(File.open(File.join(dir, "test.key")))
    @connect_count = 0
    @connections = []
    @commands = []
    @mutex = Mutex.new
    @host = 'localhost'
    @main_thread = nil
    @client_threads = []
    @fd_to_thread = {}
    listen if @options[:listen]
  end


  def listen
    @port ||= 10001
    @server = TCPServer.new(@port)
    if @options[:secure]
      context = OpenSSL::SSL::SSLContext.new
      context.cert = @certificate
      context.key = @key
      context.set_params(:verify_mode => OpenSSL::SSL::VERIFY_NONE)
      @server = OpenSSL::SSL::SSLServer.new(@server, context)
    end
    @main_thread = Thread.new do
      begin
        # puts "listening"
        loop do
          client = @server.accept
          if @options[:secure]
            client.sync_close = true
          end
          @connections << client
          @connect_count += 1
          @fd_to_thread[fd_for_socket(client)] = Thread.new(client) do |socket|
            loop do
              begin
                command = socket.gets.to_s.chomp.strip
                if !command.empty?
                  @mutex.synchronize do
                    commands << command
                  end
                  cmd, _ = command.split
                  if %w[hello authenticate].include?(cmd)
                    if @options[:response]
                      if @options[:authenticate]
                        socket.puts "ok"
                      else
                        socket.puts "gtfo"
                      end
                    end
                  end
                end
              rescue EOFError
                retry
              rescue Exception => e
                break
              end
            end
          end
          @client_threads << @fd_to_thread[fd_for_socket(client)]
        end
      rescue Exception => err
        unless @stopping
          puts "EXCEPTION:", err unless @stopping
          retry
        end
      end
    end
    # puts "server up"
  rescue Errno::EADDRINUSE => err
    puts "#{err.inspect} failed to get port #{@port}"
    puts err.message
    @port += 1
    retry
  end

  def host_and_port
    "#{host}:#{port}"
  end

  def stop
    @stopping = true
    disconnect_all
    @main_thread.kill if @main_thread
    @main_thread = nil
    @client_threads.each { |thread| thread.kill }
    @client_threads = []
    begin
      @server.close if @server
    rescue Exception => e
    end
  end

  def fd_for_socket(socket)
    case socket
    when OpenSSL::SSL::SSLSocket
      socket.io.to_i
    else
      socket.to_i
    end
  end

  def disconnect_all
    @connections.each { |c|
      fd = fd_for_socket(c)
      if (thr = @fd_to_thread[fd])
        thr.kill
      end
      @fd_to_thread.delete(fd)
      begin
        if c.respond_to?(:sync_close=)
          c.sync_close = true
        end
        c.flush
        c.close
      rescue Exception => e
        puts e.message
        puts e.backtrace.join("\n")
      end
    }
    @connections = []
  end
end
