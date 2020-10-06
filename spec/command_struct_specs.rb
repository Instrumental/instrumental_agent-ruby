require 'spec_helper'


describe Instrumental::Command, "basic functions of command structs" do
  it "should not allow bad arguments to command#+" do
    command = Instrumental::Command.new("gauge", "abc", 1, Time.at(0), 1)

    # not a command
    expect { command + "random_stuff" }.to raise_error(ArgumentError)
    # different metric
    expect { command + Instrumental::Command.new("gauge", "xyz", 1, Time.at(0), 1) }.to raise_error(ArgumentError)
    # different time
    expect { command + Instrumental::Command.new("gauge", "xyz", 1, Time.at(999), 1) }.to raise_error(ArgumentError)    
    # nil is a no-op
    expect(command + nil).to eq(command)
    # it will change the top of the other command
    expect(command + Instrumental::Command.new("increment", "abc", 1, Time.at(0), 1))
      .to eq(Instrumental::Command.new("gauge", "abc", 2, Time.at(0), 2))
  end

  it "should add together with like commands" do
    command = Instrumental::Command.new("gauge", "abc", 1, Time.at(0), 1)
    other   = Instrumental::Command.new("gauge", "abc", 2, Time.at(0), 4)
    expect(command + other).to eq(Instrumental::Command.new("gauge", "abc", 3, Time.at(0), 5))
  end
end
