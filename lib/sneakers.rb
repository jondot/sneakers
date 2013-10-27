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

require 'sneakers/support/production_formatter'
require 'sneakers/concerns/logging'
require 'sneakers/concerns/metrics'
require 'sneakers/handlers/oneshot'
require 'sneakers/worker'
require 'sneakers/publisher'

module Sneakers

  DEFAULTS = {
    # runner
    :runner_config_file => nil,
    :metrics => nil,
    :daemonize => true,
    :start_worker_delay => 0.2,
    :workers => 4,
    :log  => 'sneakers.log',
    :pid_path => 'sneakers.pid',

    #workers
    :timeout_job_after => 5,
    :prefetch => 10,
    :threads => 10,
    :env => ENV['RACK_ENV'],
    :durable => true,
    :ack => true,
    :heartbeat => 2,
    :amqp => 'amqp://guest:guest@localhost:5672',
    :vhost => '/',
    :exchange => 'sneakers',
    :exchange_type => :direct,
    :hooks => {}
  }.freeze

  Config = DEFAULTS.dup

  def self.configure(opts={})
    # worker > userland > defaults
    Config.merge!(opts)

    setup_general_logger!
    setup_worker_concerns!
    setup_general_publisher!
    @configured = true
  end

  def self.clear!
    Config.clear
    Config.merge!(DEFAULTS.dup)
    @logger = nil
    @publisher = nil
    @configured = false
  end

  def self.run_at_front!(loglevel=Logger::INFO)
    Config[:log] = STDOUT
    Config[:daemonize] = false
    setup_general_logger!
    logger.level = loglevel
  end

  def self.logger
    @logger
  end

  def self.publish(msg, routing)
    @publisher.publish(msg, routing)
  end

  def self.configured?
    @configured
  end


private

  def self.setup_general_logger!
    @logger = Logger.new(Config[:log])
    @logger.formatter = Sneakers::Support::ProductionFormatter
  end

  def self.setup_worker_concerns!
    Worker.configure_logger(Sneakers::logger)
    Worker.configure_metrics(Config[:metrics])
    Config[:handler] ||= Sneakers::Handlers::Oneshot
  end

  def self.setup_general_publisher!
    @publisher = Sneakers::Publisher.new
  end
end

