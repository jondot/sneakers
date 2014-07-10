require "sneakers/version"
require 'thread/pool'
require 'bunny'
require 'logger'

module Sneakers
  module Handlers
  end
  module Concerns
  end
end

require 'sneakers/configuration'
require 'sneakers/support/production_formatter'
require 'sneakers/concerns/logging'
require 'sneakers/concerns/metrics'
require 'sneakers/handlers/oneshot'
require 'sneakers/worker'
require 'sneakers/publisher'

module Sneakers

  Config = Configuration.new

  class << self

    def configure(opts={})
      # worker > userland > defaults
      Config.merge!(opts)

      setup_general_logger!
      setup_worker_concerns!
      setup_general_publisher!
      @configured = true
    end

    def clear!
      Config.clear
      @logger = nil
      @publisher = nil
      @configured = false
    end

    def daemonize!(loglevel=Logger::INFO)
      Config[:log] = 'sneakers.log'
      Config[:daemonize] = true
      setup_general_logger!
      logger.level = loglevel
    end

    def logger
      @logger
    end

    def publish(msg, routing)
      @publisher.publish(msg, routing)
    end

    def configured?
      @configured
    end

    private

    def setup_general_logger!
      if [:info, :debug, :error, :warn].all?{ |meth| Config[:log].respond_to?(meth) }
        @logger = Config[:log]
      else
        @logger = Logger.new(Config[:log])
        @logger.formatter = Sneakers::Support::ProductionFormatter
      end
    end

    def setup_worker_concerns!
      Worker.configure_logger(Sneakers::logger)
      Worker.configure_metrics(Config[:metrics])
      Config[:handler] ||= Sneakers::Handlers::Oneshot
    end

    def setup_general_publisher!
      @publisher = Sneakers::Publisher.new
    end
  end
end

