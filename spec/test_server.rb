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
      @server = OpenSSL::SSL::SSLServer.new(@server, context)
    end
    @main_thread = Thread.new do
      begin
        # puts "listening"
        loop do
          client = @server.accept
          @connections << client
          @connect_count += 1
          @fd_to_thread[fd_for_socket(client)] = Thread.new(client) do |socket|
            # puts "connection received"
            loop do
              begin
                command = ""
                while (c = socket.read(1)) != "\n"
                  command << c unless c.nil?
                end
                if !command.empty?
                  # puts "got: #{command}"
                  commands << command
                  if %w[hello authenticate].include?(command.split(' ')[0])
                    if @options[:response]
                      if @options[:authenticate]
                        socket.puts "ok"
                      else
                        socket.puts "gtfo"
                      end
                    end
                  end
                end
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
      if (thr = @fd_to_thread[fd_for_socket(c)])
        thr.kill
      end
      @fd_to_thread.delete(fd_for_socket(c))
      c.close rescue false
    }
    @connections = []
  end
end
