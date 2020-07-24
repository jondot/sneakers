require 'spec_helper'
require 'sneakers'
require 'rake'
require 'sneakers/tasks'

describe '' do
  class TestWorker
    include Sneakers::Worker
  end

  class TestClass1 < TestWorker; end
  class TestClass2 < TestWorker; end

  def with_workers_env(workers)
    undefine, restore = if ENV.key?('WORKERS')
                        [false, ENV['WORKERS']]
                      else
                        true
                      end
    ENV['WORKERS'] = workers
    yield
  ensure
    undefine ? ENV.delete('WORKERS') : ENV['WORKERS'] = restore
  end

  def with_rake_worker_classes(workers)
    restore = Sneakers.rake_worker_classes
    Sneakers.rake_worker_classes = workers
    yield
  ensure
    Sneakers.rake_worker_classes = restore
  end

  let(:opts) { {} }

  let :runner do
    mock = Minitest::Mock.new
    mock.expect(:run, nil)
    mock.expect(:call, mock, [expected_workers, opts])
    mock
  end

  let :run_rake_task do
    Rake::Task['sneakers:run'].reenable
    Rake.application.invoke_task 'sneakers:run'
  end

  describe 'without any settings' do
    let(:expected_workers) { [TestWorker] }

    it 'runs classes directly including the Worker' do
      Sneakers::Runner.stub :new, runner do
        run_rake_task
      end
      runner.verify
    end
  end

  describe 'with rake_worker_classes set' do
    let(:expected_workers) { [TestClass1, TestClass2] }

    it 'runs the classes from the setting' do
      with_rake_worker_classes([TestClass1, TestClass2]) do
        Sneakers::Runner.stub :new, runner do
          run_rake_task
        end
        runner.verify
      end
    end
  end

  describe 'with rake_worker_classes set, overriden by WORKERS env' do
    let(:expected_workers) { [TestClass2] }

    it 'runs the classes from the setting' do
      with_rake_worker_classes([TestClass1, TestClass2]) do
        with_workers_env('TestClass2') do
          Sneakers::Runner.stub :new, runner do
            run_rake_task
          end
          runner.verify
        end
      end
    end
  end

  describe 'with rake_worker_classes responding to call' do
    let(:expected_workers) { [TestClass1] }

    it 'runs the classes from the setting' do
      with_rake_worker_classes(-> { [TestClass1] }) do
        Sneakers::Runner.stub :new, runner do
          run_rake_task
        end
        runner.verify
      end
    end
  end
end