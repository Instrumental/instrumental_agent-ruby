require 'instrumental/version'
require 'instrumental/ssl'
require 'instrumental/system_timer'
require 'json'
require 'logger'
require 'net/http'
require 'thread'
require 'uri'
require 'zlib'

module Instrumental
  class Agent
    BACKOFF               = 2.0
    MAX_RECONNECT_DELAY   = 15
    MAX_BUFFER            = 5000
    REPLY_TIMEOUT         = 10
    CONNECT_TIMEOUT       = 20
    EXIT_FLUSH_TIMEOUT    = 5
    SECURE_COLLECTOR_URL  = "https://collector.instrumentalapp.com/report"
    COLLECTOR_URL         = "http://collector.instrumentalapp.com/report"

    attr_accessor :host, :port, :synchronous, :queue
    attr_reader :connection, :enabled

    def self.logger=(l)
      @logger = l
    end

    def self.logger
      if !@logger
        @logger = Logger.new(STDERR)
        @logger.level = Logger::WARN
      end
      @logger
    end

    def self.default_collector
      ssl_available? ? SECURE_COLLECTOR_URL : COLLECTOR_URL
    end

    def self.ssl_available?
      INSTRUMENTAL_SSL_AVAILABLE
    end

    # Sets up a connection to the collector.
    #
    #  Instrumental::Agent.new(API_KEY)
    #  Instrumental::Agent.new(API_KEY, :collector => 'hostname:port')
    def initialize(api_key, options = {})
      # symbolize options keys
      options.replace(
        options.inject({}) { |m, (k, v)| m[(k.to_sym rescue k) || k] = v; m }
      )

      # defaults
      # collector:          https://collector.instrumentalapp.com/report
      # reporting_interval: 10
      # max_commands:       1024
      # gzip:               true
      # enabled:            true
      # synchronous:        false
      @api_key            = api_key
      @uri                = URI(options[:collector] || self.class.default_collector)
      if @uri.scheme == "https" && !self.class.ssl_available?
        raise "SSL is not currently supported on your platform, please reinstall Ruby or specify a non https endpoint like #{COLLECTOR_URL}"
      end
      @reporting_interval = options[:reporting_interval] || 10
      @max_commands       = options[:max_commands] || 1024
      @gzip               = options[:gzip].nil? ? true : options[:gzip]
      @enabled            = options.has_key?(:enabled) ? !!options[:enabled] : true
      @synchronous        = !!options[:synchronous]
      @pid                = Process.pid
      @allow_reconnect    = true

      setup_cleanup_at_exit if @enabled
    end

    # Store a gauge for a metric, optionally at a specific time.
    #
    #  agent.gauge('load', 1.23)
    def gauge(metric, value, time = Time.now, count = 1)
      if valid?(metric, value, time, count) &&
          send_command("gauge", metric, value, time.to_i, count.to_i)
        value
      else
        nil
      end
    rescue Exception => e
      report_exception(e)
      nil
    end

    # Store the duration of a block in a metric. multiplier can be used
    # to scale the duration to desired unit or change the duration in
    # some meaningful way.
    #
    #  agent.time('response_time') do
    #    # potentially slow stuff
    #  end
    #
    #  agent.time('response_time_in_ms', 1000) do
    #    # potentially slow stuff
    #  end
    #
    #  ids = [1, 2, 3]
    #  agent.time('find_time_per_post', 1 / ids.size.to_f) do
    #    Post.find(ids)
    #  end
    def time(metric, multiplier = 1)
      start = Time.now
      begin
        result = yield
      ensure
        finish = Time.now
        duration = finish - start
        gauge(metric, duration * multiplier, start)
      end
      result
    end

    # Calls time and changes durations into milliseconds.
    def time_ms(metric, &block)
      time(metric, 1000, &block)
    end

    # Increment a metric, optionally more than one or at a specific time.
    #
    #  agent.increment('users')
    def increment(metric, value = 1, time = Time.now, count = 1)
      if valid?(metric, value, time, count) &&
          send_command("increment", metric, value, time.to_i, count.to_i)
        value
      else
        nil
      end
    rescue Exception => e
      report_exception(e)
      nil
    end

    # Send a notice to the server (deploys, downtime, etc.)
    #
    #  agent.notice('A notice')
    def notice(note, time = Time.now, duration = 0)
      if valid_note?(note)
        send_command("notice", time.to_i, duration.to_i, note)
        note
      else
        nil
      end
    rescue Exception => e
      report_exception(e)
      nil
    end

    # Synchronously flush all pending metrics out to the server
    # By default will not try to reconnect to the server if a
    # connection failure happens during the flush, though you
    # may optionally override this behavior by passing true.
    #
    #  agent.flush
    def flush(allow_reconnect = false)
      queue_message(nil, {
        :synchronous => true,
        :allow_reconnect => allow_reconnect
      }) if running?
    end

    def enabled?
      @enabled
    end

    def connected?
      @socket && !@socket.closed?
    end

    def logger=(logger)
      @logger = logger
    end

    def logger
      @logger || self.class.logger
    end

    # Stopping the agent will immediately stop all communication
    # to Instrumental.  If you call this and submit another metric,
    # the agent will start again.
    #
    # Calling stop will cause all metrics waiting to be sent to be
    # discarded.  Don't call it unless you are expecting this behavior.
    #
    # agent.stop
    #
    def stop
      if @timer
        @timer.kill
        @timer = nil
      end
      if @thread
        @thread.kill
        @thread = nil
      end
    end

    # Called when a process is exiting to give it some extra time to
    # push events to the service. An at_exit handler is automatically
    # registered for this method, but can be called manually in cases
    # where at_exit is bypassed like Resque workers.
    def cleanup
      if running?
        logger.info "Cleaning up agent, queue size: #{@queue.size}, thread running: #{@thread.alive?}"
        @allow_reconnect = false
        if @queue.size > 0
          queue_message(nil, { :exit => true })
          @thread.wakeup
          begin
            with_timeout(EXIT_FLUSH_TIMEOUT) { @thread.join }
          rescue Timeout::Error
            if @queue.size > 0
              logger.error "Timed out working agent thread on exit, dropping #{@queue.size} metrics"
            else
              logger.error "Timed out Instrumental Agent, exiting"
            end
          end
        end
      end
    end

    private

    def with_timeout(time, &block)
      InstrumentalTimeout.timeout(time) { yield }
    end

    def valid_note?(note)
      note !~ /[\n\r]/
    end

    def valid?(metric, value, time, count)
      valid_metric = metric =~ /^([\d\w\-_]+\.)*[\d\w\-_]+$/i
      valid_value  = value.to_s =~ /^-?\d+(\.\d+)?(e-\d+)?$/

      return true if valid_metric && valid_value

      report_invalid_metric(metric) unless valid_metric
      report_invalid_value(metric, value) unless valid_value
      false
    end

    def report_invalid_metric(metric)
      increment "agent.invalid_metric"
      logger.warn "Invalid metric #{metric}"
    end

    def report_invalid_value(metric, value)
      increment "agent.invalid_value"
      logger.warn "Invalid value #{value.inspect} for #{metric}"
    end

    def report_exception(e)
      logger.error "Exception occurred: #{e.message}\n#{e.backtrace.join("\n")}"
    end

    def send_command(cmd, *args)
      if enabled?
        start_connection_worker if !running?

        cmd = [cmd, args.collect { |a| a.to_s }.join(" ")]
        if @queue.size < MAX_BUFFER
          @queue_full_warning = false
          logger.debug "Queueing: #{cmd.inspect}"
          queue_message(cmd, { :synchronous => @synchronous })
        else
          if !@queue_full_warning
            @queue_full_warning = true
            logger.warn "Queue full(#{@queue.size}), dropping commands..."
          end
          logger.debug "Dropping command, queue full(#{@queue.size}): #{cmd.inspect}"
          nil
        end
      end
    end

    def queue_message(message, options = {})
      if @enabled
        options ||= {}
        if options[:allow_reconnect].nil?
          options[:allow_reconnect] = @allow_reconnect
        end
        synchronous = options.delete(:synchronous)
        if synchronous
          options[:sync_resource] ||= ConditionVariable.new
          @sync_mutex.synchronize {
            @queue << [message, options]
            @thread.wakeup
            options[:sync_resource].wait(@sync_mutex)
          }
        else
          @queue << [message, options]
        end
      end
      message
    end

    def start_connection_worker
      if enabled?
        @pid         = Process.pid
        @queue       = Queue.new
        @sync_mutex  = Mutex.new
        @failures    = 0

        logger.info "Starting threads"
        @thread = Thread.new do
          run_worker_loop
        end
        @timer = Thread.new(@reporting_interval, @thread) do |reporting_interval, wakeup_thread|
          run_timer_loop(reporting_interval, wakeup_thread)
        end
      end
    end

    def run_timer_loop(interval, target_thread)
      loop do
        sleep(interval)
        if target_thread.alive?
          target_thread.wakeup
        else
          return
        end
      end
    end

    def run_worker_loop
      @failures = 0
      queued_commands = []
      loop do
        has_ssl            = self.class.ssl_available?
        http               = Net::HTTP.new(@uri.host, @uri.port)
        http.use_ssl       = @uri.scheme == "https" if has_ssl
        http.open_timeout  = CONNECT_TIMEOUT
        http.ssl_timeout   = CONNECT_TIMEOUT
        http.read_timeout  = REPLY_TIMEOUT
        if has_ssl && http.use_ssl?
          http.verify_mode = OpenSSL::SSL::VERIFY_PEER
          http.ca_file     = "some-bundled-ca-file" # TODO
        end
        outgoing = {}
        syncs = []
        exit_loop = false
        while @queue.size > 0 && outgoing.size < @max_commands
          command_and_args, command_options = @queue.pop
          if (sync_resource = command_options && command_options[:sync_resource])
            syncs << sync_resource
          end
          case command_and_args
          when nil
            if command_options[:exit]
              exit_loop = true
              break
            end
          when Array
            queued_commands << command_and_args
            command, args = command_and_args
            logger.debug "Sending: #{command_and_args.inspect}"
            outgoing[command] ||= []
            outgoing[command] << args
          end
        end
        do_stop = outgoing.size < @max_commands
        unless outgoing.empty?
          request                          = Net::HTTP::Post.new(@uri.path)
          request["User-Agent"]            = "Instrumental.Agent.Ruby,#{Instrumental::VERSION}"
          request["Authorization"]         = @api_key
          request["Content-Type"]          = "application/json"
          request["X-Forwarded-For"]       = Socket.gethostname
          request["X-Forwarded-Proto"]     = @uri.scheme
          if @gzip
            compressed_outgoing = StringIO.new
            begin
              request["Content-Encoding"]  = "gzip"
              gz = Zlib::GzipWriter.new(compressed_outgoing)
              gz.write(outgoing.to_json)
            ensure
              gz.close
            end
            request.body = compressed_outgoing.string
          else
            request.body = outgoing.to_json
          end
          with_timeout(REPLY_TIMEOUT) do
            http.request(request) do |response|
              logger.debug("Sent #{outgoing.size} metrics, got HTTP code #{response.code}")
            end
          end
          queued_commands = []
        end
        syncs.each do |resource|
          @sync_mutex.synchronize do
            resource.signal
          end
        end
        if exit_loop
          logger.info "Exiting, #{@queue.size} commands remain"
          return true
        elsif do_stop
          Thread.stop
        end
      end
    rescue Exception => err
      if err.is_a?(EOFError)
        # nop
      elsif err.is_a?(Errno::ECONNREFUSED)
        logger.error "unable to connect to Instrumental."
      else
        report_exception(err)
      end
      if @allow_reconnect == false ||
        (command_options && command_options[:allow_reconnect] == false)
        logger.info "Not trying to reconnect"
        return
      end
      if queued_commands.size > 0
        logger.debug "requeueing #{queued_commands.size} commands"
        queued_commands.each do |command_and_args|
          if @queue.size < MAX_BUFFER
            @queue << command_and_args
          end
        end
      end
      @failures += 1
      delay = [(@failures - 1) ** BACKOFF, MAX_RECONNECT_DELAY].min
      logger.error "error, #{@failures} failures in a row, reconnect in #{delay}..."
      sleep delay
      retry
    end

    def setup_cleanup_at_exit
      at_exit do
        cleanup
      end
    end

    def running?
      !@thread.nil? && @pid == Process.pid
    end

  end

end
