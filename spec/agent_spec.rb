require 'spec_helper'

def wait(n=0.2, &block)
  start = Time.now
  if block_given?
    begin
      yield
    rescue Exception => ex
      if (Time.now - start) < 5
        sleep n
        retry
      else
        raise ex
      end
    end
  else
    sleep n
  end
end

FORK_SUPPORTED = begin
                   Process.wait(fork { true })
                   true
                 rescue Exception => e
                   false
                 end



shared_examples "Instrumental Agent" do
  context do

    # Inferred:
    # secure? and verify_cert? are set

    # Agent options
    let(:enabled)      { true }
    let(:synchronous)  { false }
    let(:token)        { 'test_token' }
    let(:address)      { server.host_and_port }
    let(:metrician)    { false }
    let(:frequency)    { 0 }
    let(:agent)        { Instrumental::Agent.new(token, :collector => address, :synchronous => synchronous, :enabled => enabled, :secure => secure?, :verify_cert => verify_cert?, :metrician => metrician, :frequency => frequency) }

    # Server options
    let(:listen)       { true }
    let(:response)     { true }
    let(:authenticate) { true }
    let(:server)       { TestServer.new(:listen => listen, :authenticate => authenticate, :response => response, :secure => secure?) }

    # Time Travel Options
    let(:start_of_minute) do
      now = Time.now.to_i
      Time.at(now - (now % 60))
    end

    before do
      Instrumental::Agent.logger.level = Logger::UNKNOWN
      @server = server
      wait
    end

    after do
      agent.stop
      server.stop
    end

    describe Instrumental::Agent, "disabled" do
      let(:enabled) { false }

      it "should not connect to the server" do
        expect(server.connect_count).to eq(0)
      end

      it "should not connect to the server after receiving a metric" do
        agent.gauge('disabled_test', 1)
        wait do
          expect(server.connect_count).to eq(0)
        end
      end

      it "should no op on flush without reconnect" do
        1.upto(100) { agent.gauge('disabled_test', 1) }
        agent.flush(false)
        wait do
          expect(server.commands).to be_empty
        end
      end

      it "should no op on flush with reconnect" do
        1.upto(100) { agent.gauge('disabled_test', 1) }
        agent.flush(true)
        wait do
          expect(server.commands).to be_empty
        end
      end

      it "should no op on an empty flush" do
        agent.flush(true)
        wait do
          expect(server.commands).to be_empty
        end
      end

      it "should send metrics to logger" do
        Timecop.freeze
        now = Time.now
        expect(agent.logger).to receive(:debug).with("gauge metric 1 #{now.to_i} 1")
        agent.gauge("metric", 1)
      end
    end

    describe Instrumental::Agent, "enabled" do

      it "should not connect to the server" do
        expect(server.connect_count).to eq(0)
      end

      it "should connect to the server after sending a metric" do
        agent.increment("test.foo")
        wait do
          expect(server.connect_count).to eq(1)
        end
      end

      it "should announce itself, and include version" do
        agent.increment("test.foo")
        wait do
          expect(server.commands[0]).to match(/hello .*/)
        end
        expect(server.commands[0]).to match(/ version /)
        expect(server.commands[0]).to match(/ hostname /)
        expect(server.commands[0]).to match(/ pid /)
        expect(server.commands[0]).to match(/ runtime /)
        expect(server.commands[0]).to match(/ platform /)
      end

      it "should authenticate using the token" do
        agent.increment("test.foo")
        wait do
          expect(server.commands[1]).to eq("authenticate test_token")
        end
      end

      it "should report a gauge" do
        Timecop.freeze
        now = Time.now
        agent.gauge('gauge_test', 123)
        wait do
          expect(server.commands.last).to eq("gauge gauge_test 123 #{now.to_i} 1")
        end
      end

      it "should report a time as gauge and return the block result" do
        now = Time.now
        return_value = agent.time("time_value_test") do
          1 + 1
        end
        expect(return_value).to eq(2)
        wait do
          expect(server.commands.last).to match(/gauge time_value_test .* #{now.to_i}/)
        end
      end

      it "should report a time_ms as gauge and return the block result" do
        allow(Time).to receive(:now).and_return(100)
        return_value = agent.time_ms("time_value_test") do
          allow(Time).to receive(:now).and_return(101)
          1 + 1
        end
        expect(return_value).to eq(2)
        wait do
          expect(server.commands.last).to match(/gauge time_value_test 1000/)
        end
      end

      it "should return the value gauged" do
        expect(agent.gauge('gauge_test', 123)).to eq(123)
        expect(agent.gauge('gauge_test', 989)).to eq(989)
      end

      it "should report a gauge with a set time" do
        agent.gauge('gauge_test', 123, 555)
        wait do
          expect(server.commands.last).to eq("gauge gauge_test 123 555 1")
        end
      end

      it "should report a gauge with a set time and count" do
        agent.gauge('gauge_test', 123, 555, 111)
        wait do
          expect(server.commands.last).to eq("gauge gauge_test 123 555 111")
        end
      end

      it "should report an increment" do
        now = Time.now
        agent.increment("increment_test")
        wait do
          expect(server.commands.last).to eq("increment increment_test 1 #{now.to_i} 1")
        end
      end

      it "should return the value incremented by" do
        expect(agent.increment("increment_test")).to eq(1)
        expect(agent.increment("increment_test", 5)).to eq(5)
      end

      it "should report an increment a value" do
        now = Time.now
        agent.increment("increment_test", 2)
        wait do
          expect(server.commands.last).to eq("increment increment_test 2 #{now.to_i} 1")
        end
      end

      it "should report an increment with a set time" do
        agent.increment('increment_test', 1, 555)
        wait do
          expect(server.commands.last).to eq("increment increment_test 1 555 1")
        end
      end

      it "should report an increment with a set time and count" do
        agent.increment('increment_test', 1, 555, 111)
        wait do
          expect(server.commands.last).to eq("increment increment_test 1 555 111")
        end
      end

      context do
        let(:listen) { false }
        it "should discard data that overflows the buffer" do
          with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
            allow(agent.logger).to receive(:debug)
            expect(agent.logger).to receive(:debug).with("Dropping command, queue full(3): increment overflow_test 4 300 1")
            expect(agent.logger).to receive(:debug).with("Dropping command, queue full(3): increment overflow_test 5 300 1")
            1.upto(5) do |i|
              agent.increment('overflow_test', i, 300)
            end

            wait
            expect(agent.sender_queue.size).to eq(3)
            expect(agent.sender_queue.pop.first.to_s).to start_with("increment overflow_test 1 300 1")
            expect(agent.sender_queue.pop.first.to_s).to start_with("increment overflow_test 2 300 1")
            expect(agent.sender_queue.pop.first.to_s).to start_with("increment overflow_test 3 300 1")
            expect(agent.sender_queue.size).to eq(0)
          end
        end
      end

      it "should send all data in synchronous mode" do
        with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
          agent.synchronous = true
          5.times do |i|
            agent.increment('overflow_test', i + 1, 300)
          end
          expect(agent.instance_variable_get(:@sender_queue).size).to eq(0)
          wait # let the server receive the commands
          expect(server.commands).to include("increment overflow_test 1 300 1")
          expect(server.commands).to include("increment overflow_test 2 300 1")
          expect(server.commands).to include("increment overflow_test 3 300 1")
          expect(server.commands).to include("increment overflow_test 4 300 1")
          expect(server.commands).to include("increment overflow_test 5 300 1")
        end
      end

      if FORK_SUPPORTED
        it "should automatically reconnect when forked" do
          agent.increment('fork_reconnect_test', 1, 2)
          fork do
            agent.increment('fork_reconnect_test', 1, 3) # triggers reconnect
          end

          wait(1)
          agent.increment('fork_reconnect_test', 1, 4) # triggers reconnect

          wait(1)
          expect(server.connect_count).to eq(2)

          expect(server.commands).to include("increment fork_reconnect_test 1 2 1")
          expect(server.commands).to include("increment fork_reconnect_test 1 3 1")
          expect(server.commands).to include("increment fork_reconnect_test 1 4 1")
        end
      end

      it "shouldn't start multiple background threads" do
        # Force a wait that would cause a race condition
        allow(agent).to receive(:disconnect) {
          sleep 1
        }

        run_sender_loop_calls = 0
        allow(agent).to receive(:run_sender_loop) {
          run_sender_loop_calls += 1
          sleep 3 # keep the worker thread alive
        }

        t = Thread.new { agent.increment("race") }
        agent.increment("race")
        wait(2)
        expect(run_sender_loop_calls).to eq(1)
        expect(agent.sender_queue.size).to eq(2)
      end

      it "should never let an exception reach the user" do
        expect(agent).to receive(:send_command).twice { raise(Exception.new("Test Exception")) }
        expect(agent.increment('throws_exception', 2)).to eq(nil)
        wait do
          expect(agent.increment('throws_exception', 234)).to eq(nil)
        end
      end

      it "should let exceptions in time bubble up" do
        expect { agent.time('za') { raise "fail" } }.to raise_exception(StandardError)
      end

      it "should return nil if the user overflows the MAX_BUFFER" do
        allow_any_instance_of(Queue).to receive(:pop).and_return(nil)
        1.upto(Instrumental::Agent::MAX_BUFFER) do
          expect(agent.increment("test")).to eq(1)
        end
        expect(agent.increment("test")).to eq(nil)
      end

      it "should allow reasonable metric names" do
        agent.increment('a')
        agent.increment('a.b')
        agent.increment('hello.world')
        agent.increment('ThisIsATest.Of.The.Emergency.Broadcast.System.12345')
        wait do
          expect(server.commands.join("\n")).to_not include("increment agent.invalid_metric")
        end
      end

      it "should track invalid values" do
        expect(agent.logger).to receive(:warn).with(/hello.*testington/)
        agent.increment('testington', 'hello')
        wait do
          expect(server.commands.join("\n")).to include("increment agent.invalid_value")
        end
      end

      it "should allow reasonable values" do
        agent.increment('a', -333.333)
        agent.increment('a', -2.2)
        agent.increment('a', -1)
        agent.increment('a',  0)
        agent.increment('a',  1)
        agent.increment('a',  2.2)
        agent.increment('a',  333.333)
        agent.increment('a',  Float::EPSILON)
        wait do
          expect(server.commands.join("\n")).to_not include("increment agent.invalid_value")
        end
      end

      it "should send notices to the server" do
        Timecop.freeze
        tm = Time.now
        agent.notice("Test note", tm)
        wait do
          expect(server.commands.join("\n")).to include("notice #{tm.to_i} 0 Test note")
        end
      end

      it "should prevent a note w/ newline characters from being sent to the server" do
        expect(agent.notice("Test_bad_note\n")).to eq(nil)

        # Send a note that make it through so we're sure the bad note would have
        # arrived if it was going to.
        Timecop.freeze
        tm = Time.now
        agent.notice("Test_good_note", tm)
        wait do
          expect(server.commands.join("\n")).to include("Test_good_note")
        end

        expect(server.commands.join("\n")).to_not include("Test_bad_note")
      end

      it "should allow outgoing metrics to be stopped" do
        tm = Time.now
        agent.increment("foo.bar", 1, tm)
        agent.stop

        # In Java the test server hangs sometimes when the agent disconnects so
        # this cleans up the server.
        server.stop
        wait
        server.listen

        wait
        agent.increment("foo.baz", 1, tm)
        wait do
          expect(server.commands.join("\n")).to include("increment foo.baz 1 #{tm.to_i}")
        end
        expect(server.commands.join("\n")).to_not include("increment foo.bar 1 #{tm.to_i}")
      end

      it "should allow flushing pending values to the server" do
        1.upto(100) { agent.gauge('a', rand(50)) }
        expect(agent.instance_variable_get(:@sender_queue).size).to be > 0
        agent.flush
        expect(agent.instance_variable_get(:@sender_queue).size).to eq(0)
        wait do
          expect(server.commands.grep(/^gauge a /).size).to eq(100)
        end
      end

      it "should no op on an empty flush" do
        agent.flush(true)
        wait do
          expect(server.commands).to be_empty
        end
      end
    end

    describe Instrumental::Agent, "connection problems" do
      it "should automatically reconnect on disconnect" do
        agent.increment("reconnect_test1", 1, 1234)
        wait do
          expect(server.commands.grep(/reconnect_test1/).size).to eq(1)
        end
        server.disconnect_all
        wait(1)
        agent.increment('reconnect_test', 1, 5678) # triggers reconnect
        wait do
          expect(server.connect_count).to eq(2)
          # Ensure the last command sent has been received after the reconnect attempt
          expect(server.commands.last).to eq("increment reconnect_test 1 5678 1")
        end
      end

      context 'not listening' do
        # Mark server as down
        let(:listen) { false }

        it "should buffer commands when server is down" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # The agent should not have sent the metric yet, the server is not responding
          expect(agent.sender_queue.pop(true).first.to_s).to eq("increment reconnect_test 1 1234 1")
        end

        it "should warn once when buffer is full" do
          with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
            wait
            expect(agent.logger).to receive(:warn).with(/Queue full/).once

            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
          end
        end
      end

      context 'bad address' do
        let(:address) { "bad-address:9999" }

        it "should not be running if it cannot connect" do
          expect(Resolv).to receive(:getaddresses).with("bad-address").and_raise Resolv::ResolvError
          agent.gauge('connection_test', 1, 1234)
          expect(agent.send(:running?)).to eq(false)
        end
      end

      context 'not responding' do
        # Server will not acknowledge hello or authenticate commands
        let(:response) { false }

        it "should buffer commands when server is not responsive" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # Since server hasn't responded to hello or authenticate, worker thread will not send data
          expect(agent.sender_queue.pop(true).first.to_s).to eq("increment reconnect_test 1 1234 1")
        end
      end

      context 'server hangup' do
        it "should cancel the worker thread when the host has hung up" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure1', 1, 1234)
          wait do
            expect(server.commands.grep(/connection_failure/).size).to eq(1)
          end
          # Stop the server
          server.stop
          wait
          # Send one metric to the stopped server
          agent.gauge('connection_failure2', 1, 1234)
          # The agent thread should have stopped running since the network write would
          # have failed. The queue will still contain the metric that has yet to be sent
          wait do
            expect(agent.send(:running?)).to eq(false)
          end
          expect(agent.sender_queue.size).to eq(1)
        end

        it "should restart the worker thread after hanging it up during an unreachable host event" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure', 1, 1234)
          wait do
            expect(server.commands.grep(/connection_failure/).size).to eq(1)
          end
          # Stop the server
          server.stop
          wait
          # Send one metric to the stopped server
          agent.gauge('connection_failure', 1, 1234)
          # The agent thread should have stopped running since the network write would
          # have failed. The queue will still contain the metric that has yet to be sent
          wait do
            expect(agent.send(:running?)).to eq(false)
          end
          expect(agent.sender_queue.size).to eq(1)
          # Start the server back up again
          server.listen
          # Sending another metric should kickstart the background worker thread
          agent.gauge('connection_failure', 1, 1234)
          # The agent should now be running the background thread, and the queue should be empty
          wait do
            expect(agent.send(:running?)).to eq(true)
            expect(agent.sender_queue.size).to eq(0)
          end
        end

        it "should restart the worker thread after hanging it up during a bad ssl handshake event" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure', 1, 1234)
          wait do
            expect(server.commands.grep(/connection_failure/).size).to eq(1)
          end
          # Make the agent return the relevant exception on the next connection test
          test_connection_fail = true
          tc = agent.method(:test_connection)
          allow(agent).to receive(:test_connection) do |*args, &block|
            test_connection_fail ? raise(OpenSSL::SSL::SSLError.new) : tc.call(*args)
          end

          # Send one metric to the agent
          agent.gauge('connection_failure', 1, 1234)
          # The agent thread should have stopped running since the network write would
          # have failed.
          wait do
            expect(agent.send(:running?)).to eq(false)
          end
          # The command is not in the queue
          expect(agent.sender_queue.size).to eq(0)
          # allow the agent to behave normally
          test_connection_fail = false
          # Sending another metric should kickstart the background worker thread
          agent.gauge('connection_failure', 1, 1234)
          # The agent should now be running the background thread, and the queue should be empty
          wait do
            expect(agent.send(:running?)).to eq(true)
            expect(agent.sender_queue.size).to eq(0)
            expect(server.commands.grep(/connection_failure/).size).to eq(2)
          end
        end

        it "should accurately count failures so that backoff can work as intended" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure', 1, 1234)
          wait do
            expect(server.commands.grep(/connection_failure/).size).to eq(1)
          end

          # configure test_connection to fail in a way that won't kill the inner loop
          test_connection_fail = true
          tc = agent.method(:test_connection)
          allow(agent).to receive(:test_connection) do |*args, &block|
            test_connection_fail ? raise("test_connection_fail") : tc.call(*args)
          end

          # send some metrics
          agent.gauge('connection_failure_1', 1, 1234)
          agent.gauge('connection_failure_2', 1, 1234)
          agent.gauge('connection_failure_3', 1, 1234)
          wait do
            expect(agent.instance_variable_get(:@failures)).to be > 0
            expect(agent.sender_queue.size).to be > 0
          end

          # let the loop proceed
          test_connection_fail = false

          wait do
            expect(agent.send(:running?)).to eq(true)
            expect(agent.sender_queue.size).to eq(0)
          end
        end
      end

      context 'not authenticating' do
        # Server will fail all authentication attempts
        let(:authenticate) { false }

        it "should buffer commands when authentication fails" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # Metrics should not have been sent since all authentication failed
          expect(agent.sender_queue.pop(true).first.to_s).to eq("increment reconnect_test 1 1234 1")
        end
      end

      if FORK_SUPPORTED
        it "should send commands in a short-lived process" do
          if pid = fork { agent.increment('foo', 1, 1234) }
            Process.wait(pid)
            # The forked process should have flushed and waited on at_exit
            expect(server.commands.last).to eq("increment foo 1 1234 1")
          end
        end

        it "should send commands in a process that bypasses at_exit when using #cleanup" do
          if pid = fork { agent.increment('foo', 1, 1234); agent.cleanup; exit! }
            Process.wait(pid)
            # The forked process should have flushed and waited on at_exit since cleanup was called explicitly
            expect(server.commands.last).to eq("increment foo 1 1234 1")
          end
        end

        it "should not wait longer than EXIT_FLUSH_TIMEOUT seconds to exit a process" do
          allow(agent).to receive(:open_socket) { |*args, &block| sleep(5) && block.call }
          with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 3) do
            if (pid = fork { agent.increment('foo', 1) })
              tm = Time.now.to_f
              Process.wait(pid)
              diff = Time.now.to_f - tm
              expect(diff.abs).to be >= 3
              expect(diff.abs).to be < 5
            end
          end
        end

        it "should follow normal exit procedures whether or not there are commands queued" do
          allow(agent).to receive(:open_socket) { |*args, &block| sleep(5) && block.call }
          with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 1) do
            if (pid = fork { agent.increment('foo', 1); agent.sender_queue.clear })
              tm = Time.now.to_f
              Process.wait(pid)
              diff = Time.now.to_f - tm
              expect(diff).to be < 2
              expect(diff).to be > 1
            end
          end
        end
      end

      it "should not wait much longer than EXIT_FLUSH_TIMEOUT to attempt flushing the socket when disconnecting" do
        agent.increment('foo', 1)
        wait do
          expect(server.commands.grep(/foo/).size).to eq(1)
        end
        expect(agent).to receive(:flush_socket) do
          r, w = IO.pipe
          Thread.new do # JRuby requires extra thread here according to e9bb707e
            begin
              IO.select([r]) # mimic an endless blocking select poll
            rescue Object => ex
              # This rescue-raise prevents JRuby from printing a backtrace at
              # the end of the run complaining about an exception in this thread.
              raise
            end
          end.join
        end.at_least(1).times

        with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 3) do
          tm = Time.now.to_f
          agent.cleanup
          diff = Time.now.to_f - tm
          expect(diff).to be <= 3.1
        end
      end

      it "should not attempt to resolve DNS more than RESOLUTION_FAILURES_BEFORE_WAITING before introducing an inactive period" do
        with_constants('Instrumental::Agent::RESOLUTION_FAILURES_BEFORE_WAITING' => 1,
                       'Instrumental::Agent::RESOLUTION_WAIT' => 2,
                       'Instrumental::Agent::RESOLVE_TIMEOUT' => 0.1) do
          attempted_resolutions = 0
          allow(Resolv).to receive(:getaddresses) { attempted_resolutions +=1 ; sleep 1 }
          agent.gauge('test', 1)
          expect(attempted_resolutions).to eq(1)
          expect(agent.send(:running?)).to eq(false)
          agent.gauge('test', 1)
          expect(attempted_resolutions).to eq(1)
          expect(agent.send(:running?)).to eq(false)
        end
      end

      it "should attempt to resolve DNS after the RESOLUTION_WAIT inactive period has been exceeded" do
        with_constants('Instrumental::Agent::RESOLUTION_FAILURES_BEFORE_WAITING' => 1,
                       'Instrumental::Agent::RESOLUTION_WAIT' => 2,
                       'Instrumental::Agent::RESOLVE_TIMEOUT' => 0.1) do
          attempted_resolutions = 0
          allow(Resolv).to receive(:getaddresses) { attempted_resolutions +=1 ; sleep 1 }
          agent.gauge('test', 1)
          expect(attempted_resolutions).to eq(1)
          expect(agent.send(:running?)).to eq(false)
          agent.gauge('test', 1)
          expect(attempted_resolutions).to eq(1)
          expect(agent.send(:running?)).to eq(false)
          sleep 2
          agent.gauge('test', 1)
          expect(attempted_resolutions).to eq(2)
        end
      end

      it "should attempt to resolve DNS after a connection timeout" do
        with_constants('Instrumental::Agent::CONNECT_TIMEOUT' => 1) do
          attempted_opens = 0
          open_sleep = 0
          os = agent.method(:open_socket)
          allow(agent).to receive(:open_socket) { |*args, &block| attempted_opens +=1 ; sleep(open_sleep) && os.call(*args) }

          # Connect normally and start running worker loop
          attempted_resolutions = 0
          ga = Resolv.method(:getaddresses)
          allow(Resolv).to receive(:getaddresses) { |*args, &block| attempted_resolutions +=1 ; ga.call(*args) }
          agent.gauge('test', 1)
          wait 2
          expect(attempted_resolutions).to eq(1)
          expect(attempted_opens).to eq(1)
          expect(agent.send(:running?)).to eq(true)

          # Setup a failure for the next command so we'll break out of the inner
          # loop in run_sender_loop causing another call to open_socket
          test_connection_fail = true
          tc = agent.method(:test_connection)
          allow(agent).to receive(:test_connection) { |*args, &block| test_connection_fail ? raise("fail") : tc.call(*args) }

          # Setup a timeout failure in open_socket for the next command
          open_sleep = 5

          # 1. test_connection fails, triggering a retry, which hits open_socket
          # 2. we hit open_socket, it times out causing worker thread to end
          agent.gauge('test', 1)
          wait 5
          # On retry we attempt to open_socket, but this times out
          expect(attempted_opens).to eq(2)
          # We don't resolve again yet, we just disconnect
          expect(attempted_resolutions).to eq(1)
          expect(agent.send(:running?)).to eq(false)

          # Make test_connection succeed on the next command
          test_connection_fail = false
          # Make open_socket succeed again
          open_sleep = 0

          # We reconnect on the next command
          # The reconnect causes a new DNS resolution
          agent.gauge('test', 1)
          wait 5
          expect(attempted_resolutions).to eq(2)
          expect(attempted_opens).to eq(3)
          expect(agent.send(:running?)).to eq(true)
        end
      end
    end

    describe Instrumental::Agent, "enabled with sync option" do
      let(:synchronous) { true }

      it "should send all data in synchronous mode" do
        with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
          5.times do |i|
            agent.increment('overflow_test', i + 1, 300)
          end
          wait # let the server receive the commands
          expect(server.commands).to include("increment overflow_test 1 300 1")
          expect(server.commands).to include("increment overflow_test 2 300 1")
          expect(server.commands).to include("increment overflow_test 3 300 1")
          expect(server.commands).to include("increment overflow_test 4 300 1")
          expect(server.commands).to include("increment overflow_test 5 300 1")
        end
      end
    end

    describe Instrumental::Agent, "metrician" do
      context "enabled" do
        let(:metrician) { true }

        it "is enabled by default" do
          a = agent
          expect(Metrician.agent).to eq(a)
        end

        it "uses agent logger" do
          new_logger = double
          agent.logger = new_logger
          expect(Metrician.logger).to eq(new_logger)
        end
      end

      context "disabled" do
        let(:metrician) { false }

        it "can be disbaled" do
          expect(Metrician).to_not receive(:activate)
          agent = Instrumental::Agent.new('test-token', :metrician => false)
        end
      end
    end

    describe Instrumental::Agent, "aggregation" do
      context "aggregation enabled" do
        let(:frequency) { 2 }

        it "can be enabled at Agent.new time" do
          expect(agent.frequency).to eq(2)
        end

        it "can be modified by setting the agent frequency" do
          agent.frequency = 15
          expect(agent.frequency).to eq(15)
        end

        it "is disabled by default" do
          agent = Instrumental::Agent.new('test_token')
          expect(agent.frequency.to_f).to eq(0)
        end

        it "should only allow frequencies that align with minutes" do
          (-5..100).each do |freq|
            agent.frequency = freq
            expect(Instrumental::Agent::VALID_FREQUENCIES).to include(agent.frequency)
          end
        end

        it "bypasses aggregator queue entirely for most commands when frequency == 0" do
          agent.frequency = 0 # this is red - 0 for green
          expect(Instrumental::EventAggregator).not_to receive(:new)
          agent.increment('a_metric')
        end

        it "adds data to the event aggregator and does not immediately send it" do
          Timecop.travel start_of_minute
          agent.increment('test')
          wait do
            expect(agent.instance_variable_get(:@event_aggregator).size).to eq(1)
            expect(agent.instance_variable_get(:@event_aggregator).values.values.first.metric).to eq('test')
          end
        end

        it "batches data before sending" do
          Timecop.freeze do
            agent.increment('a_metric')
            agent.increment('a_metric')
            agent.increment('another_metric')
          end
          agent.flush(true)
          wait do
            expect(server.commands.grep(/_metric/).size).to eq(2)
            aggregated_metric = server.commands.grep(/a_metric/).first.split(" ")
            expect(aggregated_metric[2].to_i).to eq(2) # value
            expect(aggregated_metric[4].to_i).to eq(2) # count
          end
        end

        it "aggregates to the specified frequency within the aggregator" do
          Timecop.travel(start_of_minute)
          agent.frequency = 15
          expect(agent.frequency).not_to be(Instrumental::Agent::DEFAULT_FREQUENCY)
          agent.increment('metric', 1, Time.at(0))

          # will get aligned to the closest frequency (15)
          agent.increment('metric', 1, Time.at(20))
          wait do
            expect(agent.instance_variable_get(:@event_aggregator).values.keys).to eq(["metric:0", "metric:15"])
          end
          agent.flush
          wait do
            expect(server.commands.grep(/metric 1 0/).size).to eq(1)
            expect(server.commands.grep(/metric 1 15/).size).to eq(1)
          end
        end

        it "flushes data from both queues before sending" do
          Timecop.freeze do
            100.times do |i|
              agent.increment("test_metric_#{i}")
              agent.increment("other_metric")
            end
          end

          expect(agent.instance_variable_get(:@aggregator_queue).size).to be > 0
          agent.flush
          expect(agent.instance_variable_get(:@sender_queue).size).to eq(0)
          expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(0)

          wait do
            expect(server.commands.grep(/test_metric/).size).to eq(100)
            expect(server.commands.grep(/other_metric/).size).to eq(1)
          end
        end

        it "does not batch notices" do
          agent.frequency = 60
          agent.notice "things are happening", 0, 100
          agent.notice "things are happening", 0, 100
          agent.notice "things are happening", 0, 100
          wait do
            expect(server.commands.grep(/things are happening/).size).to eq(3)
          end
        end

        it "can be disabled by setting frequency to nil" do
          agent.frequency = nil
          expect(Instrumental::EventAggregator).not_to receive(:new)
          agent.increment('metric')
          wait do
            expect(server.commands.grep(/metric/).size).to eq(1)
          end
        end

        it "can be disabled by setting frequency to 0" do
          agent.frequency = 0
          expect(Instrumental::EventAggregator).not_to receive(:new)
          agent.increment('metric')
          wait do
            expect(server.commands.grep(/metric/).size).to eq(1)
          end
        end

        it "automatically uses the highest-without-going-over frequency for a bad frequency" do
          agent.frequency = 17
          expect(agent.frequency).to eq(15)
          agent.frequency = 69420
          expect(agent.frequency).to eq(60)
          agent.frequency = 0
          expect(agent.frequency).to eq(0)
          agent.frequency = -1
          expect(agent.frequency).to eq(0)
        end

        it "can take strings as frequency" do
          agent = Instrumental::Agent.new('test_token', :frequency => "15")
          expect(agent.frequency).to eq(15)
        end

        it "should not be enabled at the same time as synchronous" do
          expect(Instrumental::Agent.logger).to receive(:warn).with(/Synchronous and Frequency should not be enabled at the same time! Defaulting to synchronous mode./)
          agent = Instrumental::Agent.new('test_token', :synchronous => true, :frequency => 6)
          expect(agent.synchronous).to eq(true)
          expect(agent.frequency).to eq(0)
        end

        it "should use synchronous mode if it is enabled, even if turned on after frequency set at start" do
          agent.increment('metric')
          agent.increment('metric')
          agent.synchronous = true
          agent.increment('metric')
          wait do
            expect(server.commands.grep(/metric 1/).size).to eq(1)
          end
          agent.flush
          wait do
            expect(server.commands.grep(/metric 1/).size).to eq(1)
            expect(server.commands.grep(/metric 2/).size).to eq(1)
          end
        end

        it "sends aggregated metrics after specified frequency, even if no flush is sent" do
          agent.frequency = 1
          Timecop.travel(start_of_minute)
          agent.increment('metric')
          agent.increment('metric')
          agent.gauge('other', 1)
          agent.gauge('other', 1)
          agent.gauge('other', 1)
          sleep (0.5)
          wait { expect(server.commands.grep(/metric/).size).to eq(0) }
          sleep (0.51) # total sleep > 1 frequency

          expect(server.commands.grep(/metric 2/).size).to eq(1)
          expect(server.commands.grep(/other 3/).size).to eq(1)
        end

        it "if aggregator is at max size, next command will force a forward to the sender thread" do
          Timecop.travel(start_of_minute)
          with_constants('Instrumental::Agent::MAX_AGGREGATOR_SIZE' => 3) do
            agent.increment('overflow_test1')
            agent.increment('overflow_test2')
            agent.increment('overflow_test3')
            agent.increment('overflow_test4')
            agent.increment('overflow_test5')

            # only 1 because the 5th command triggers a forward of the first 4
            wait do
              expect(agent.instance_variable_get(:@event_aggregator).size).to eq(1)
            end
            agent.flush
            wait do
              expect(server.commands.grep(/overflow_test/).size).to eq(5)
            end
          end
        end

        context do
          let(:listen) { false }
          it "will not send aggregators to the sender queue if the sender thread is not ready" do
            Timecop.travel(start_of_minute)
            agent.frequency = 1

            with_constants('Instrumental::Agent::MAX_BUFFER' => 3,
                          'Instrumental::Agent::MAX_AGGREGATOR_SIZE' => 4) do

              # fill the queue
              agent.increment('overflow_test1')
              agent.increment('overflow_test2')
              agent.increment('overflow_test3')

              # wait until they are all in the aggregator
              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(0)
                expect(agent.instance_variable_get(:@event_aggregator).size).to eq(3)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(0)
              end

              # fill the queue again
              agent.increment('overflow_test1')
              agent.increment('overflow_test2')
              agent.increment('overflow_test3')

              # wait until they are all in the aggregator
              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(0)
                expect(agent.instance_variable_get(:@event_aggregator).size).to eq(3)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(0)
              end

              # wait for the aggregator to get forwarded and popped by the sender
              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(0)
                expect(agent.instance_variable_get(:@event_aggregator)).to eq(nil)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(1)
              end

              # fill the queue again
              agent.increment('overflow_test4')
              agent.increment('overflow_test5')
              agent.increment('overflow_test6')

              # wait for them all to be in the aggregator
              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(0)
                expect(agent.instance_variable_get(:@event_aggregator).size).to eq(3)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(1)
              end

              # sleep until the next forward is done
              sleep(agent.frequency + 0.1)

              # fill the queue again
              agent.increment('overflow_test7')
              agent.increment('overflow_test8')
              agent.increment('overflow_test9')

              # because sending is blocked, the prevous aggregator never sent
              # when it hits max size, the aggregator queue starts backing up
              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(1)
                expect(agent.instance_variable_get(:@event_aggregator).size).to eq(5)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(1)
              end

              # send 3 more items, to overflow the aggregator queue
              allow(agent.logger).to receive(:debug)
              expect(agent.logger).to receive(:debug).with("Dropping command, queue full(3): increment overflow_testc 4 300 1")
              agent.increment('overflow_testa')
              agent.increment('overflow_testb')
              agent.increment('overflow_testc', 4, 300, 1) # will get dropped

              wait do
                expect(agent.instance_variable_get(:@aggregator_queue).size).to eq(3)
                expect(agent.instance_variable_get(:@event_aggregator).size).to eq(5)
                expect(agent.instance_variable_get(:@sender_queue).size).to eq(1)
              end
            end
          end
        end

        if FORK_SUPPORTED
          it "should automatically reconnect when forked when aggregation is enabled" do
            Timecop.travel start_of_minute
            agent.frequency = 10

            agent.increment('fork_reconnect_test1', 1, 0, 1)
            fork do
              agent.increment('fork_reconnect_test2', 1, 0, 1) # triggers reconnect
              exit
            end


            sleep 1
            agent.increment('fork_reconnect_test3', 1, 0, 1) # triggers reconnect

            agent.flush
            expect(server.connect_count).to eq(2)

            wait do
              expect(server.commands).to include("increment fork_reconnect_test1 1 0 1")
              expect(server.commands).to include("increment fork_reconnect_test2 1 0 1")
              expect(server.commands).to include("increment fork_reconnect_test3 1 0 1")
              expect(server.commands.grep(/fork_reconnect/).size).to eq(3)
            end
          end
        end
      end
    end
  end
end

describe "Insecure" do
  let(:secure?) { false }
  let(:verify_cert?) { false }
  it_behaves_like "Instrumental Agent"
end

describe "Secure without cert verify" do
  let(:secure?) { true }
  let(:verify_cert?) { false }
  it_behaves_like "Instrumental Agent"

  it "should be disabled if the system does not allow secure connections but the user specifically requested secure" do
    allow_any_instance_of(Instrumental::Agent).to receive(:allows_secure?).and_return(false)
    agent = Instrumental::Agent.new('test-token', :enabled => true, :secure => true)
    expect(agent.secure).to eq(false)
    expect(agent.enabled).to eq(false)
  end

  it "should be fallback to insecure if the system does not allow secure connections but the user did not specifically request secure" do
    allow_any_instance_of(Instrumental::Agent).to receive(:allows_secure?) { false }
    agent = Instrumental::Agent.new('test-token', :enabled => true)
    expect(agent.secure).to eq(false)
    expect(agent.enabled).to eq(true)
  end
end
