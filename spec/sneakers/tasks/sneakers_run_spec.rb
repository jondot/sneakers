require 'spec_helper'
require 'sneakers'
require 'rake'
require 'sneakers/tasks'

describe 'Worker classes run by rake sneakers:run' do
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

  def with_sneakers_worker_classes_reset
    restore = Sneakers::Worker::Classes.clone
    Sneakers::Worker::Classes.replace([])
    yield
  ensure
    Sneakers::Worker::Classes.replace(restore)
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
    let(:expected_workers) { [worker_class] }
    let(:worker_class) { Class.new.tap { |klass| klass.send(:include, Sneakers::Worker) } }

    it 'runs classes directly including the Worker' do
      with_workers_env(nil) do
        with_sneakers_worker_classes_reset do
          Sneakers::Runner.stub :new, runner do
            run_rake_task
          end
          runner.verify
        end
      end
    end
  end

  describe 'with rake_worker_classes set' do
    let(:expected_workers) { [TestClass1, TestClass2] }

    it 'runs the classes from the setting' do
      with_workers_env(nil) do
        with_rake_worker_classes([TestClass1, TestClass2]) do
          Sneakers::Runner.stub :new, runner do
            run_rake_task
          end
          runner.verify
        end
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
      with_workers_env(nil) do
        with_rake_worker_classes(-> { [TestClass1] }) do
          Sneakers::Runner.stub :new, runner do
            run_rake_task
          end
          runner.verify
        end
      end
    end
  end
end