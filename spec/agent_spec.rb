require 'spec_helper'

def wait(n=0.2)
  sleep n # FIXME: hack
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
    let(:agent)        { Instrumental::Agent.new(token, :collector => address, :synchronous => synchronous, :enabled => enabled, :secure => secure?, :verify_cert => verify_cert?) }

    # Server options
    let(:listen)       { true }
    let(:response)     { true }
    let(:authenticate) { true }
    let(:server)       { TestServer.new(:listen => listen, :authenticate => authenticate, :response => response, :secure => secure?) }

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
        server.connect_count.should == 0
      end

      it "should not connect to the server after receiving a metric" do
        agent.gauge('disabled_test', 1)
        wait
        server.connect_count.should == 0
      end

      it "should no op on flush without reconnect" do
        1.upto(100) { agent.gauge('disabled_test', 1) }
        agent.flush(false)
        wait
        server.commands.should be_empty
      end

      it "should no op on flush with reconnect" do
        1.upto(100) { agent.gauge('disabled_test', 1) }
        agent.flush(true)
        wait
        server.commands.should be_empty
      end

      it "should no op on an empty flush" do
        agent.flush(true)
        wait
        server.commands.should be_empty
      end

      it "should send metrics to logger" do
        now = Time.now
        agent.logger.should_receive(:debug).with("gauge metric 1 #{now.to_i} 1")
        agent.gauge("metric", 1)
      end
    end

    describe Instrumental::Agent, "enabled" do

      it "should not connect to the server" do
        server.connect_count.should == 0
      end

      it "should show as authenticated" do
        agent.authenticate!
        agent.should be_authenticated
      end

      it "should connect to the server after sending a metric" do
        agent.increment("test.foo")
        wait
        server.connect_count.should == 1
      end

      it "should announce itself, and include version" do
        agent.increment("test.foo")
        wait
        server.commands[0].should =~ /hello .*/
        server.commands[0].should =~ / version /
        server.commands[0].should =~ / hostname /
        server.commands[0].should =~ / pid /
        server.commands[0].should =~ / runtime /
        server.commands[0].should =~ / platform /
      end

      it "should authenticate using the token" do
        agent.increment("test.foo")
        wait
        server.commands[1].should == "authenticate test_token"
      end

      it "should report a gauge" do
        now = Time.now
        agent.gauge('gauge_test', 123)
        wait
        server.commands.last.should == "gauge gauge_test 123 #{now.to_i} 1"
      end

      it "should report a time as gauge and return the block result" do
        now = Time.now
        agent.time("time_value_test") do
          1 + 1
        end.should == 2
        wait
        server.commands.last.should =~ /gauge time_value_test .* #{now.to_i}/
      end

      it "should return the value gauged" do
        now = Time.now
        agent.gauge('gauge_test', 123).should == 123
        agent.gauge('gauge_test', 989).should == 989
        wait
      end

      it "should report a gauge with a set time" do
        agent.gauge('gauge_test', 123, 555)
        wait
        server.commands.last.should == "gauge gauge_test 123 555 1"
      end

      it "should report a gauge with a set time and count" do
        agent.gauge('gauge_test', 123, 555, 111)
        wait
        server.commands.last.should == "gauge gauge_test 123 555 111"
      end

      it "should report an increment" do
        now = Time.now
        agent.increment("increment_test")
        wait
        server.commands.last.should == "increment increment_test 1 #{now.to_i} 1"
      end

      it "should return the value incremented by" do
        now = Time.now
        agent.increment("increment_test").should == 1
        agent.increment("increment_test", 5).should == 5
      end

      it "should report an increment a value" do
        now = Time.now
        agent.increment("increment_test", 2)
        wait
        server.commands.last.should == "increment increment_test 2 #{now.to_i} 1"
      end

      it "should report an increment with a set time" do
        agent.increment('increment_test', 1, 555)
        wait
        server.commands.last.should == "increment increment_test 1 555 1"
      end

      it "should report an increment with a set time and count" do
        agent.increment('increment_test', 1, 555, 111)
        wait
        server.commands.last.should == "increment increment_test 1 555 111"
      end

      it "should discard data that overflows the buffer" do
        with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
          5.times do |i|
            agent.increment('overflow_test', i + 1, 300)
          end
          wait
          server.commands.should     include("increment overflow_test 1 300 1")
          server.commands.should     include("increment overflow_test 2 300 1")
          server.commands.should     include("increment overflow_test 3 300 1")

          server.commands.should_not include("increment overflow_test 4 300 1")
          server.commands.should_not include("increment overflow_test 5 300 1")
        end
      end

      it "should send all data in synchronous mode" do
        with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
          agent.synchronous = true
          5.times do |i|
            agent.increment('overflow_test', i + 1, 300)
          end
          agent.instance_variable_get(:@queue).size.should == 0
          wait # let the server receive the commands
          server.commands.should include("increment overflow_test 1 300 1")
          server.commands.should include("increment overflow_test 2 300 1")
          server.commands.should include("increment overflow_test 3 300 1")
          server.commands.should include("increment overflow_test 4 300 1")
          server.commands.should include("increment overflow_test 5 300 1")
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
          server.connect_count.should == 2
          server.commands.should include("increment fork_reconnect_test 1 2 1")
          server.commands.should include("increment fork_reconnect_test 1 3 1")
          server.commands.should include("increment fork_reconnect_test 1 4 1")
        end
      end

      it "should never let an exception reach the user" do
        agent.stub(:send_command).and_raise(Exception.new("Test Exception"))
        agent.increment('throws_exception', 2).should be_nil
        wait
        agent.gauge('throws_exception', 234).should be_nil
        wait
      end

      it "should let exceptions in time bubble up" do
        expect { agent.time('za') { raise "fail" } }.to raise_error
      end

      it "should return nil if the user overflows the MAX_BUFFER" do
        Queue.any_instance.stub(:pop) { nil }
        1.upto(Instrumental::Agent::MAX_BUFFER) do
          agent.increment("test").should == 1
        end
        agent.increment("test").should be_nil
      end

      it "should track invalid metrics" do
        agent.logger.should_receive(:warn).with(/%%/)
        agent.increment(' %% .!#@$%^&*', 1, 1)
        wait
        server.commands.join("\n").should include("increment agent.invalid_metric")
      end

      it "should allow reasonable metric names" do
        agent.increment('a')
        agent.increment('a.b')
        agent.increment('hello.world')
        agent.increment('ThisIsATest.Of.The.Emergency.Broadcast.System.12345')
        wait
        server.commands.join("\n").should_not include("increment agent.invalid_metric")
      end

      it "should track invalid values" do
        agent.logger.should_receive(:warn).with(/hello.*testington/)
        agent.increment('testington', 'hello')
        wait
        server.commands.join("\n").should include("increment agent.invalid_value")
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
        wait
        server.commands.join("\n").should_not include("increment agent.invalid_value")
      end

      it "should send notices to the server" do
        tm = Time.now
        agent.notice("Test note", tm)
        wait
        server.commands.join("\n").should include("notice #{tm.to_i} 0 Test note")
      end

      it "should prevent a note w/ newline characters from being sent to the server" do
        agent.notice("Test note\n").should be_nil
        wait
        server.commands.join("\n").should_not include("notice Test note")
      end

      it "should allow outgoing metrics to be stopped" do
        tm = Time.now
        agent.increment("foo.bar", 1, tm)
        agent.stop
        wait
        agent.increment("foo.baz", 1, tm)
        wait
        server.commands.join("\n").should include("increment foo.baz 1 #{tm.to_i}")
        server.commands.join("\n").should_not include("increment foo.bar 1 #{tm.to_i}")
      end

      it "should allow flushing pending values to the server" do
        1.upto(100) { agent.gauge('a', rand(50)) }
        agent.instance_variable_get(:@queue).size.should > 0
        agent.flush
        agent.instance_variable_get(:@queue).size.should ==  0
        wait
        server.commands.grep(/^gauge a /).size.should == 100
      end

      it "should no op on an empty flush" do
        agent.flush(true)
        wait
        server.commands.should be_empty
      end
    end

    describe Instrumental::Agent, "connection problems" do
      it "should automatically reconnect on disconnect" do
        agent.increment("reconnect_test", 1, 1234)
        wait
        server.disconnect_all
        wait(1)
        agent.increment('reconnect_test', 1, 5678) # triggers reconnect
        wait(1)
        server.connect_count.should == 2
        # Ensure the last command sent has been received after the reconnect attempt
        server.commands.last.should == "increment reconnect_test 1 5678 1"
      end

      context 'not listening' do
        # Mark server as down
        let(:listen) { false }

        it "should buffer commands when server is down" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # The agent should not have sent the metric yet, the server is not responding
          agent.queue.pop(true).should include("increment reconnect_test 1 1234 1\n")
        end

        it "should warn once when buffer is full" do
          with_constants('Instrumental::Agent::MAX_BUFFER' => 3) do
            wait
            agent.logger.should_receive(:warn).with(/Queue full/).once

            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
            agent.increment('buffer_full_warn_test', 1, 1234)
          end
        end
      end

      context 'bad address' do
        let(:address) { "nope:9999" }

        it "should not be running if it cannot connect" do
          agent.gauge('connection_test', 1, 1234)
          # nope:9999 does not resolve to anything, the agent will not resolve
          # the address and refuse to start a worker thread
          agent.should_not be_running
        end
      end

      context 'not responding' do
        # Server will not acknowledge hello or authenticate commands
        let(:response) { false }

        it "should buffer commands when server is not responsive" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # Since server hasn't responded to hello or authenticate, worker thread will not send data
          agent.queue.pop(true).should include("increment reconnect_test 1 1234 1\n")
        end
      end

      context 'server hangup' do
        it "should cancel the worker thread when the host has hung up" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure', 1, 1234)
          wait
          # Stop the server
          server.stop
          wait
          # Send one metric to the stopped server
          agent.gauge('connection_failure', 1, 1234)
          wait
          # The agent thread should have stopped running since the network write would
          # have failed. The queue will still contain the metric that has yet to be sent
          agent.should_not be_running
          agent.queue.size.should == 1

        end

        it "should restart the worker thread after hanging it up during an unreachable host event" do
          # Start the background agent thread and let it send one metric successfully
          agent.gauge('connection_failure', 1, 1234)
          wait
          # Stop the server
          server.stop
          wait
          # Send one metric to the stopped server
          agent.gauge('connection_failure', 1, 1234)
          wait
          # The agent thread should have stopped running since the network write would
          # have failed. The queue will still contain the metric that has yet to be sent
          agent.should_not be_running
          agent.queue.size.should == 1
          wait
          # Start the server back up again
          server.listen
          wait
          # Sending another metric should kickstart the background worker thread
          agent.gauge('connection_failure', 1, 1234)
          wait
          # The agent should now be running the background thread, and the queue should be empty
          agent.should be_running
          agent.queue.size.should == 0
        end

      end


      context 'not authenticating' do
        # Server will fail all authentication attempts
        let(:authenticate) { false }

        it "should buffer commands when authentication fails" do
          agent.increment('reconnect_test', 1, 1234)
          wait
          # Metrics should not have been sent since all authentication failed
          agent.queue.pop(true).should include("increment reconnect_test 1 1234 1\n")
        end

        it "should not be authenticated" do
          agent.should_not be_authenticated
        end
      end

      if FORK_SUPPORTED
        it "should send commands in a short-lived process" do
          if pid = fork { agent.increment('foo', 1, 1234) }
            Process.wait(pid)
            # The forked process should have flushed and waited on at_exit
            server.commands.last.should == "increment foo 1 1234 1"
          end
        end

        it "should send commands in a process that bypasses at_exit when using #cleanup" do
          if pid = fork { agent.increment('foo', 1, 1234); agent.cleanup; exit! }
            Process.wait(pid)
            # The forked process should have flushed and waited on at_exit since cleanup was called explicitly
            server.commands.last.should == "increment foo 1 1234 1"
          end
        end

        it "should not wait longer than EXIT_FLUSH_TIMEOUT seconds to exit a process" do
          agent.stub(:open_socket) { |*args, &block| sleep(5) && block.call }
          with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 3) do
            if (pid = fork { agent.increment('foo', 1) })
              tm = Time.now.to_f
              Process.wait(pid)
              diff = Time.now.to_f - tm
              diff.abs.should >= 3
              diff.abs.should < 5
            end
          end
        end

        it "should not wait to exit a process if there are no commands queued" do
          agent.stub(:open_socket) { |*args, &block| sleep(5) && block.call }
          with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 3) do
            if (pid = fork { agent.increment('foo', 1); agent.queue.clear })
              tm = Time.now.to_f
              Process.wait(pid)
              diff = Time.now.to_f - tm
              diff.should < 1
            end
          end
        end
      end

      it "should not wait longer than EXIT_FLUSH_TIMEOUT to attempt flushing the socket when disconnecting" do
        agent.increment('foo', 1)
        wait
        agent.should_receive(:flush_socket) do
          r, w = IO.pipe
          Thread.new do
            IO.select([r]) # mimic an endless blocking select poll
          end.join
        end
        with_constants('Instrumental::Agent::EXIT_FLUSH_TIMEOUT' => 3) do
          tm = Time.now.to_f
          agent.cleanup
          diff = Time.now.to_f - tm
          diff.should <= 3
        end
      end

      it "should not attempt to resolve DNS more than RESOLUTION_FAILURES_BEFORE_WAITING before introducing an inactive period" do
        with_constants('Instrumental::Agent::RESOLUTION_FAILURES_BEFORE_WAITING' => 1,
                       'Instrumental::Agent::RESOLUTION_WAIT' => 2,
                       'Instrumental::Agent::RESOLVE_TIMEOUT' => 0.1) do
          attempted_resolutions = 0
          Resolv.stub(:getaddresses) { attempted_resolutions +=1 ; sleep 1 }
          agent.gauge('test', 1)
          attempted_resolutions.should == 1
          agent.should_not be_running
          agent.gauge('test', 1)
          attempted_resolutions.should == 1
          agent.should_not be_running
        end
      end

      it "should attempt to resolve DNS after the RESOLUTION_WAIT inactive period has been exceeded" do
        with_constants('Instrumental::Agent::RESOLUTION_FAILURES_BEFORE_WAITING' => 1,
                       'Instrumental::Agent::RESOLUTION_WAIT' => 2,
                       'Instrumental::Agent::RESOLVE_TIMEOUT' => 0.1) do
          attempted_resolutions = 0
          Resolv.stub(:getaddresses) { attempted_resolutions +=1 ; sleep 1 }
          agent.gauge('test', 1)
          attempted_resolutions.should == 1
          agent.should_not be_running
          agent.gauge('test', 1)
          attempted_resolutions.should == 1
          agent.should_not be_running
          sleep 2
          agent.gauge('test', 1)
          attempted_resolutions.should == 2
        end
      end

      it "should attempt to resolve DNS after a connection timeout" do
        with_constants('Instrumental::Agent::CONNECT_TIMEOUT' => 1) do
          attempted_opens = 0
          open_sleep = 0
          os = agent.method(:open_socket)
          agent.stub(:open_socket) { |*args, &block| attempted_opens +=1 ; sleep(open_sleep) && os.call(*args) }

          # Connect normally and start running worker loop
          attempted_resolutions = 0
          ga = Resolv.method(:getaddresses)
          Resolv.stub(:getaddresses) { |*args, &block| attempted_resolutions +=1 ; ga.call(*args) }
          agent.gauge('test', 1)
          wait 2
          attempted_resolutions.should == 1
          attempted_opens.should == 1
          agent.should be_running

          # Setup a failure for the next command so we'll break out of the inner
          # loop in run_worker_loop causing another call to open_socket
          test_connection_fail = true
          tc = agent.method(:test_connection)
          agent.stub(:test_connection) { |*args, &block| test_connection_fail ? raise("fail") : tc.call(*args) }

          # Setup a timeout failure in open_socket for the next command
          open_sleep = 5

          # 1. test_connection fails, triggering a retry, which hits open_socket
          # 2. we hit open_socket, it times out causing worker thread to end
          agent.gauge('test', 1)
          wait 5
          # On retry we attempt to open_socket, but this times out
          attempted_opens.should == 2
          # We don't resolve again yet, we just disconnect
          attempted_resolutions.should == 1
          agent.should_not be_running

          # Make test_connection succeed on the next command
          test_connection_fail = false
          # Make open_socket succeed again
          open_sleep = 0

          # We reconnect on the next command
          # The reconnect causes a new DNS resolution
          agent.gauge('test', 1)
          wait 5
          attempted_resolutions.should == 2
          attempted_opens.should == 3
          agent.should be_running
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
          server.commands.should include("increment overflow_test 1 300 1")
          server.commands.should include("increment overflow_test 2 300 1")
          server.commands.should include("increment overflow_test 3 300 1")
          server.commands.should include("increment overflow_test 4 300 1")
          server.commands.should include("increment overflow_test 5 300 1")
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
    Instrumental::Agent.any_instance.stub(:allows_secure?) { false }
    agent = Instrumental::Agent.new('test-token', :enabled => true, :secure => true)
    agent.secure.should  == false
    agent.enabled.should == false
  end

it "should be fallback to insecure if the system does not allow secure connections but the user did not specifically request secure" do
    Instrumental::Agent.any_instance.stub(:allows_secure?) { false }
    agent = Instrumental::Agent.new('test-token', :enabled => true)
    agent.secure.should  == false
    agent.enabled.should == true
  end
end
