require 'logger'
require 'spec_helper'
require 'sneakers'
require 'sneakers/runner'

class DummyFlag
  def wait_for_set(*)
    true
  end
end

class DummyEngine
  include Sneakers::WorkerGroup

  attr_reader :config

  def initialize(config)
    @config = config
    @stop_flag = DummyFlag.new
  end
end

class DefaultsWorker
  include Sneakers::Worker
  from_queue 'defaults'

  def work(msg); end
end

class StubbedWorker
  attr_reader :opts

  def initialize(_, _, opts)
    @opts = opts
  end

  def run
    true
  end
end

describe Sneakers::WorkerGroup do
  let(:logger) { Logger.new('log/logtest.log') }
  let(:connection) { Bunny.new(host: 'any-host.local') }
  let(:runner) { Sneakers::Runner.new([DefaultsWorker]) }
  let(:runner_config) { runner.instance_variable_get('@runnerconfig') }
  let(:config) { runner_config.reload_config! }
  let(:engine) { DummyEngine.new(config) }

  describe '#run' do
    describe 'with connecion provided' do
      before do
        Sneakers.clear!
        Sneakers.configure(connection: connection, log: logger)
      end

      it 'creates workers with connection: connection' do
        DefaultsWorker.stub(:new, ->(*args) { StubbedWorker.new(*args) }) do
          engine.run

          workers = engine.instance_variable_get('@workers')
          workers.first.opts[:connection].must_equal(connection)
        end
      end
    end

    describe 'without connecion provided' do
      before do
        Sneakers.clear!
        Sneakers.configure(log: logger)
      end

      it 'creates workers with connection: nil' do
        DefaultsWorker.stub(:new, ->(*args) { StubbedWorker.new(*args) }) do
          engine.run

          workers = engine.instance_variable_get('@workers')
          assert_nil(workers.first.opts[:connection])
        end
      end
    end
  end
end
