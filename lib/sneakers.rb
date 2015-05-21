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
  extend self

  CONFIG = Configuration.new

  def configure(opts={})
    # worker > userland > defaults
    CONFIG.merge!(opts)

    setup_general_logger!
    setup_worker_concerns!
    setup_general_publisher!
    @configured = true
  end

  def clear!
    CONFIG.clear
    @logger = nil
    @publisher = nil
    @configured = false
  end

  def daemonize!(loglevel=Logger::INFO)
    CONFIG[:log] = 'sneakers.log'
    CONFIG[:daemonize] = true
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
    if [:info, :debug, :error, :warn].all?{ |meth| CONFIG[:log].respond_to?(meth) }
      @logger = CONFIG[:log]
    else
      @logger = ServerEngine::DaemonLogger.new(CONFIG[:log])
      @logger.formatter = Sneakers::Support::ProductionFormatter
    end
  end

  def setup_worker_concerns!
    Worker.configure_logger(Sneakers::logger)
    Worker.configure_metrics(CONFIG[:metrics])
    CONFIG[:handler] ||= Sneakers::Handlers::Oneshot
  end

  def setup_general_publisher!
    @publisher = Sneakers::Publisher.new
  end
end

