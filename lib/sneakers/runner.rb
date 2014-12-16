require 'serverengine'
require 'sneakers/workergroup'

module Sneakers
  class Runner
    def initialize(worker_classes, opts={})
      @runnerconfig = RunnerConfig.new(worker_classes, opts)
    end

    def run
      @se = ServerEngine.create(nil, WorkerGroup) { @runnerconfig.reload_config! }
      puts "mofo"
      @se.run
      "ugga"
    end

    def stop
      @se.stop
    end
  end


  class RunnerConfig
    def method_missing(meth, *args, &block)
      if %w{ before_fork after_fork }.include? meth.to_s
        @conf[meth] = block
      elsif %w{ workers start_worker_delay amqp }.include? meth.to_s
        @conf[meth] = args.first
      else
        super
      end
    end

    def initialize(worker_classes, opts)
      @worker_classes = worker_classes
      @conf = opts
    end

    def to_h
      @conf
    end


    def reload_config!
      Sneakers.logger.warn("Loading runner configuration...")
      config_file = Sneakers::CONFIG[:runner_config_file]

      if config_file
        begin
          instance_eval(File.read(config_file), config_file)
          Sneakers.logger.info("Loading config with file: #{config_file}")
        rescue
          Sneakers.logger.error("Cannot load from file '#{config_file}', #{$!}")
        end
      end

      config = make_serverengine_config

      [:before_fork, :after_fork].each do | hook |
        Sneakers::CONFIG[:hooks][hook] = config.delete(hook) if config[hook]
      end


      Sneakers.logger.info("New configuration: #{config.inspect}")
      config
    end

  private
    def make_serverengine_config
      Sneakers::CONFIG.merge(@conf).merge({
        :worker_type => 'process',
        :worker_classes => @worker_classes
      })
    end
  end

end
