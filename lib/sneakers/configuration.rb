require 'forwardable'

module Sneakers
  class Configuration

    extend Forwardable
    def_delegators :@hash, :to_hash, :[], :[]=, :==, :fetch, :delete, :has_key?

    DEFAULTS = {
      # runner
      :runner_config_file => nil,
      :metrics            => nil,
      :daemonize          => false,
      :start_worker_delay => 0.2,
      :workers            => 4,
      :log                => STDOUT,
      :pid_path           => 'sneakers.pid',
      :amqp_heartbeat     => 10,

      # workers
      :timeout_job_after  => 5,
      :prefetch           => 10,
      :threads            => 10,
      :durable            => true,
      :ack                => true,
      :heartbeat          => 2,
      :exchange           => 'sneakers',
      :exchange_type      => :direct,
      :exchange_arguments => {}, # Passed as :arguments to Bunny::Channel#exchange
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
      hash = hash.dup

      # parse vhost from amqp if vhost is not specified explicitly, only
      # if we're not given a connection to use.
      if hash[:connection].nil?
        if hash[:vhost].nil? && !hash[:amqp].nil?
          hash[:vhost] = AMQ::Settings.parse_amqp_url(hash[:amqp]).fetch(:vhost, '/')
        end
      else
        # If we are given a Bunny object, ignore params we'd otherwise use to
        # create one.  This removes any question about where config params are
        # coming from, and makes it more likely that downstream code that needs
        # this info gets it from the right place.
        [:vhost, :amqp, :heartbeat].each do |k|
          hash.delete(k)
          @hash.delete(k)
        end
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
