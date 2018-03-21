require 'sneakers/version'
require 'concurrent/executors'
require 'bunny'
require 'logger'
require 'serverengine'

module Sneakers
  module Handlers
  end
  module Concerns
  end
end

require 'sneakers/configuration'
require 'sneakers/errors'
require 'sneakers/support/production_formatter'
require 'sneakers/concerns/logging'
require 'sneakers/concerns/metrics'
require 'sneakers/handlers/oneshot'
require 'sneakers/content_type'
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

  def logger=(logger)
    @logger = logger
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

  def server=(server)
    @server = server
  end

  def server?
    @server
  end

  def configure_server
    yield self if server?
  end

  # Register a proc to handle any error which occurs within the Sneakers process.
  #
  #   Sneakers.error_reporters << proc { |exception, worker, context_hash| MyErrorService.notify(exception, context_hash) }
  #
  # The default error handler logs errors to Sneakers.logger.
  # Ripped off from https://github.com/mperham/sidekiq/blob/6ad6a3aa330deebd76c6cf0d353f66abd3bef93b/lib/sidekiq.rb#L165-L174
  def error_reporters
    CONFIG[:error_reporters]
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

