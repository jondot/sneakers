require 'sneakers/error_reporter'
require 'forwardable'

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
      # Set up default handler which just logs the error.
      # Remove this in production if you don't want sensitive data logged.
      :error_reporters => [Sneakers::ErrorReporter::DefaultLogger.new],

      # runner
      :runner_config_file => nil,
      :metrics            => nil,
      :daemonize          => false,
      :start_worker_delay => 0.2,
      :workers            => 4,
      :log                => STDOUT,
      :pid_path           => 'sneakers.pid',
      :amqp_heartbeat     => 30,

      # workers
      :prefetch           => 10,
      :threads            => 10,
      :share_threads      => false,
      :ack                => true,
      :heartbeat          => 30,
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
      hash = map_all_deprecated_options(hash)

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

      @hash = deep_merge(@hash, hash)
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
      redacted[:amqp] = redacted[:amqp].sub(/(?<=\Aamqp:\/)[^@]+(?=@)/, "<redacted>") if redacted.has_key?(:amqp)
      return redacted.inspect_without_redaction
    end
    alias_method :inspect_without_redaction, :inspect
    alias_method :inspect, :inspect_with_redaction

    def map_all_deprecated_options(hash)
      hash = map_deprecated_options_key(:exchange_options, :exchange_type, :type, true, hash)
      hash = map_deprecated_options_key(:exchange_options, :exchange_arguments, :arguments, true, hash)
      hash = map_deprecated_options_key(:exchange_options, :durable, :durable, false, hash)
      hash = map_deprecated_options_key(:queue_options, :durable, :durable, true, hash)
      hash = map_deprecated_options_key(:queue_options, :arguments, :arguments, true, hash)
      hash
    end

    def map_deprecated_options_key(target_key, deprecated_key, key, delete_deprecated_key, hash = {})
      return hash if hash[deprecated_key].nil?
      hash = deep_merge({ target_key => { key => hash[deprecated_key] } }, hash)
      hash.delete(deprecated_key) if delete_deprecated_key
      hash
    end

    def deep_merge(first, second)
      merger = proc { |_, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      first.merge(second, &merger)
    end
  end
end
