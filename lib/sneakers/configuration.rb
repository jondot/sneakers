require 'forwardable'
require 'active_support/core_ext/hash/deep_merge'

module Sneakers
  class Configuration

    extend Forwardable
    def_delegators :@hash, :to_hash, :[], :[]=, :==, :fetch, :delete, :has_key?

    EXCHANGE_OPTION_DEFAULTS = {
      :type               => :direct,
      :durable            => true,
      :auto_delete        => false,
      :arguments => {} # Passed as :arguments to Bunny::Channel#exchange
    }.freeze

    QUEUE_OPTION_DEFAULTS = {
      :durable            => true,
      :auto_delete        => false,
      :exclusive          => false,
      :arguments => {}
    }.freeze

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
      :share_threads      => false,
      :ack                => true,
      :heartbeat          => 2,
      :hooks              => {},
      :exchange           => 'sneakers',
      :exchange_options   => EXCHANGE_OPTION_DEFAULTS,
      :queue_options      => QUEUE_OPTION_DEFAULTS
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
      hash = map_deprecated_exchange_options_key(hash, :exchange_type, :type)
      hash = map_deprecated_exchange_options_key(hash, :exchange_arguments, :arguments)
      hash = map_deprecated_exchange_options_key(hash, :durable, :durable)

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

      @hash.deep_merge!(hash)
    end

    def merge(hash)
      instance = self.class.new
      instance.merge! to_hash
      instance.merge! hash
      instance
    end

    def inspect_with_redaction
      redacted = self.class.new
      redacted.merge! to_hash

      # redact passwords
      redacted[:amqp] = redacted[:amqp].sub(/(?<=\Aamqp:\/)[^@]+(?=@)/, "<redacted>")
      return redacted.inspect_without_redaction
    end
    alias_method :inspect_without_redaction, :inspect
    alias_method :inspect, :inspect_with_redaction

    def map_deprecated_exchange_options_key(hash = {}, deprecated_key, key)
      return hash if hash[deprecated_key].nil?
      hash = { exchange_options: { key => hash[deprecated_key] } }.deep_merge(hash)
      hash = { queue_options: { key => hash[deprecated_key] } }.deep_merge(hash) if deprecated_key == :durable
      hash.delete(deprecated_key)
      hash
    end
  end
end
