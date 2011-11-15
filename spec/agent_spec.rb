require 'spec_helper'

def wait
  sleep 0.2 # FIXME: hack
end

describe Instrumental::Agent, "disabled" do
  before do
    @server = TestServer.new
    @agent = Instrumental::Agent.new('test_token', :collector => @server.host_and_port, :enabled => false)
  end

  after do
    @server.stop
  end

  it "should not connect to the server" do
    wait
    @server.connect_count.should == 0
  end

  it "should not connect to the server" do
    wait
    @agent.gauge('disabled_test', 1)
    wait
    @server.connect_count.should == 0
  end

end

describe Instrumental::Agent, "enabled" do
  before do
    @server = TestServer.new
    @agent = Instrumental::Agent.new('test_token', :collector => @server.host_and_port)
  end

  after do
    @server.stop
  end

  it "should connect to the server" do
    wait
    @server.connect_count.should == 1
  end

  it "should announce itself, and include version" do
    wait
    @server.commands[0].should =~ /hello .*version /
  end

  it "should authenticate using the token" do
    wait
    @server.commands[1].should == "authenticate test_token"
  end

  it "should report a gauge" do
    now = Time.now
    @agent.gauge('gauge_test', 123)
    wait
    @server.commands.last.should == "gauge gauge_test 123 #{now.to_i}"
  end

  it "should report a gauge with a set time" do
    @agent.gauge('gauge_test', 123, 555)
    wait
    @server.commands.last.should == "gauge gauge_test 123 555"
  end

  it "should report an increment" do
    now = Time.now
    @agent.increment("increment_test")
    wait
    @server.commands.last.should == "increment increment_test 1 #{now.to_i}"
  end

  it "should report an increment a value" do
    now = Time.now
    @agent.increment("increment_test", 2)
    wait
    @server.commands.last.should == "increment increment_test 2 #{now.to_i}"
  end

  it "should report an increment with a set time" do
    @agent.increment('increment_test', 1, 555)
    wait
    @server.commands.last.should == "increment increment_test 1 555"
  end

  it "should automatically reconnect" do
    wait
    @server.disconnect_all
    @agent.increment('reconnect_test', 1, 1234) # triggers reconnect
    wait
    @server.connect_count.should == 2
    @server.commands.last.should == "increment reconnect_test 1 1234"
  end
end
