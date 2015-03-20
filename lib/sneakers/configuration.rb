require 'forwardable'

module Sneakers
  class Configuration

    extend Forwardable
    def_delegators :@hash, :to_hash, :[], :[]=, :==, :fetch, :delete

    DEFAULTS = {
      # runner
      :runner_config_file => nil,
      :metrics            => nil,
      :daemonize          => false,
      :start_worker_delay => 0.2,
      :workers            => 4,
      :log                => STDOUT,
      :pid_path           => 'sneakers.pid',

      # workers
      :timeout_job_after  => 5,
      :prefetch           => 10,
      :threads            => 10,
      :durable            => true,
      :ack                => true,
      :heartbeat          => 2,
      :exchange           => 'sneakers',
      :exchange_type      => :direct,
      :hooks              => {}
    }.freeze


    def initialize
      clear
    end

    def clear
      @hash = DEFAULTS.dup
      @hash[:amqp]  = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
      @hash[:vhost] = AMQ::Settings.parse_amqp_url(@hash[:amqp]).fetch(:vhost, '/')
    end

    def merge!(hash)
      # parse vhost from amqp if vhost is not specified explicitly
      if hash[:vhost].nil? && !hash[:amqp].nil?
        hash = hash.dup
        hash[:vhost] = AMQ::Settings.parse_amqp_url(hash[:amqp]).fetch(:vhost, '/')
      end

      @hash.merge!(hash)
    end

    def merge(hash)
      instance = self.class.new
      instance.merge! to_hash
      instance.merge! hash
      instance
    end
  end
end
