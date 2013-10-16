require 'serverengine'
require 'sneakers/workergroup'
require 'sneakers/runner_config'

module Sneakers
  class Runner
    def initialize(worker_classes, opts={})
      @runnerconfig = RunnerConfig.new(worker_classes)
    end

    def run
      @se = ServerEngine.create(nil, WorkerGroup) { @runnerconfig.reload_config! }
      @se.run
    end

    def stop
      @se.stop
    end
  end
end
