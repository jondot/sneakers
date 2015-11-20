require 'logger'
require 'spec_helper'
require 'sneakers'

describe Sneakers::Runner do
  let(:logger) { Logger.new('logtest.log') }

  describe "with configuration that specifies a logger object" do
    before do
      Sneakers.configure(log: logger)
      @runner = Sneakers::Runner.new([])
    end

  end
end

