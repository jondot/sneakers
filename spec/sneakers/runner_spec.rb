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

    it 'passes the logger to serverengine' do
      # Stub out ServerEngine::Daemon.run so we only exercise the way we invoke
      # ServerEngine.create
      any_instance_of(ServerEngine::Daemon) do |daemon|
        stub(daemon).main{ return 0 }
      end

      @runner.run
      # look at @runner's @se instance variable (actually of type Daemon)...and
      # figure out what it's logger is...
    end
  end
end
