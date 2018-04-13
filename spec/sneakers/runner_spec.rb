require 'logger'
require 'spec_helper'
require 'sneakers'
require 'sneakers/runner'

describe Sneakers::Runner do
  let(:logger) { Logger.new('log/logtest.log') }

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

describe Sneakers::RunnerConfig do
  let(:logger) { Logger.new("log/logtest.log") }
  let(:runner_config) { Sneakers::Runner.new([]).instance_variable_get("@runnerconfig") }

  describe "with a connection" do
    let(:connection) { Object.new }

    before { Sneakers.configure(log: logger, connection: connection) }

    describe "#reload_config!" do
      it "does not throw exception" do
        runner_config.reload_config!
      end

      it "must not have :log key" do
        runner_config.reload_config!.has_key?(:log).must_equal false
      end

      it "must have :logger key as an instance of Logger" do
        runner_config.reload_config![:logger].is_a?(Logger).must_equal true
      end

      it "must have :connection" do
        runner_config.reload_config![:connection].is_a?(Object).must_equal true
      end
    end
  end

  describe "without a connection" do
    before { Sneakers.configure(log: logger) }

    describe "#reload_config!" do
      it "must not have :log key" do
        runner_config.reload_config!.has_key?(:log).must_equal false
      end

      it "must have :logger key as an instance of Logger" do
        runner_config.reload_config![:logger].is_a?(Logger).must_equal true
      end
    end
  end
end
