module Instrumental
  class Middleware
    def self.boot
      if @stack = detect_stack
        @stack.install_middleware
        @enabled = true
      else
        @enabled = false
      end
    end

    def self.stack; @stack; end

    def self.enabled; @enabled; end
    def self.enabled=(v); @enabled = v; end

    def initialize(app)
      @app = app
    end

    def stack
      Middleware.stack
    end

    def measure(env, &block)
      response = nil
      if Middleware.enabled
        request = Rack::Request.new(env)
        key_parts = stack.recognize_uri(request)
        if key = key_parts.join(".")
          exc = nil
          tms = Benchmark.measure do
            begin
              response = yield
            rescue Exception => e
              exc = e
            end
          end
          begin
            Agent.all.each do |agent|
              if exc
                agent.increment("%s.error.%s" % [key, exc.class])
              end
              if response && response.first
                agent.increment("%s.status.%i" % [key, response.first])
              else
                agent.increment(key)
              end
            end
          rescue Exception => e
            stack.log "Error occurred sending stats: #{e}"
            stack.log e.backtrace.join("\n")
          end
          raise exc if exc
        end
      end
      response ||= yield
    end

    def call(env)
      measure(env) do
        @app.call(env)
      end
    end

    class Stack
      def self.default_logger
        @logger ||= Logger.new('/dev/null')
      end

      def log(msg)
        Stack.default_logger.error(msg)
      end
    end

    private

    def self.detect_stack
      [Rails3, Rails23].collect { |klass| klass.create }.detect { |obj| !obj.nil? }
    end
  end
end

require 'instrumental/rack/rails3'
require 'instrumental/rack/rails23'
