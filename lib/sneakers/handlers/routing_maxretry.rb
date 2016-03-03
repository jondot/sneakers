require 'json'

module Sneakers
  module Handlers
    # This handler does basically the same as MaxRetry handler. But it does not
    # create additional exchanges. Instead it uses dead-letter routing keys to
    # create the bindings to the retry and error queues.
    class RoutingMaxretry # rubocop:disable Metrics/ClassLength
      attr_reader :opts, :exchanges, :channel, :queue

      # @param channel [Bunny::Channel]
      # @param queue [Bunny::Queue]
      # @param worker_opts [Hash]
      def initialize(channel, queue, worker_opts)
        @channel = channel
        @queue   = queue
        @opts    = init_opts(worker_opts)

        Sneakers.logger.debug { "#{log_prefix} creating handler, opts=#{worker_opts}" }

        create_queues_and_bindings
      end

      # @param delivery_info [Bunny::DeliveryInfo]
      def acknowledge(delivery_info, _, _)
        channel.acknowledge(delivery_info.delivery_tag)
      end

      # @param delivery_info [Bunny::DeliveryInfo]
      # @param message_properties [Bunny::MessageProperties]
      # @param message [String]
      # @param requeue [Boolean]
      def reject(delivery_info, message_properties, message, requeue = false)
        if requeue
          # This was explicitly rejected specifying it be requeued so we do not
          # want it to pass through our retry logic.
          channel.reject(delivery_info.delivery_tag, requeue)
        else
          handle_retry(delivery_info, message_properties, message, :reject)
        end
      end

      # @param delivery_info [Bunny::DeliveryInfo]
      # @param message_properties [Bunny::MessageProperties]
      # @param message [String]
      # @param error [String, Symbol, Exception]
      def error(delivery_info, message_properties, message, error)
        handle_retry(delivery_info, message_properties, message, error)
      end

      # @param delivery_info [Bunny::DeliveryInfo]
      # @param message_properties [Bunny::MessageProperties]
      # @param message [String]
      def timeout(delivery_info, message_properties, message)
        handle_retry(delivery_info, message_properties, message, :timeout)
      end

      def noop(_, _, _); end

      private

      def init_opts(worker_opts)
        {
          error_queue_name:    "#{queue.name}.error",
          error_routing_key:   "queue.#{queue.name}.error",
          requeue_routing_key: "queue.#{queue.name}.requeue",
          retry_max_times:     5,
          retry_queue_name:    "#{queue.name}.retry",
          retry_routing_key:   "queue.#{queue.name}.retry",
          retry_timeout:       6000,
          worker_queue_name:   queue.name
        }.merge!(worker_opts)
      end

      def create_queues_and_bindings
        create_retry_queue_and_binding
        create_error_queue_and_binding

        # Route retry messages to worker queue
        queue.bind(
          opts[:exchange],
          routing_key: opts[:requeue_routing_key]
        )
      end

      def create_error_queue_and_binding
        create_queue_and_binding(
          opts[:error_queue_name],
          opts[:error_routing_key]
        )
      end

      def create_retry_queue_and_binding
        create_queue_and_binding(
          opts[:retry_queue_name],
          opts[:retry_routing_key],
          arguments: retry_queue_arguments
        )
      end

      def retry_queue_arguments
        {
          'x-dead-letter-exchange'    => opts[:exchange],
          'x-message-ttl'             => opts[:retry_timeout],
          'x-dead-letter-routing-key' => opts[:requeue_routing_key]
        }
      end

      def create_queue_and_binding(queue_name, routing_key, arguments = {})
        Sneakers.logger.debug do
          "#{log_prefix} creating queue=#{queue_name}, arguments=#{arguments}"
        end

        created_queue = channel.queue(
          queue_name,
          { durable: queue_durable? }.merge!(arguments)
        )
        created_queue.bind(opts[:exchange], routing_key: routing_key)
      end

      def handle_retry(delivery_info, message_properties, message, reason)
        num_attempts = failure_count(message_properties.headers) + 1
        if num_attempts <= opts[:retry_max_times]
          reject_to_retry(delivery_info, message_properties, num_attempts)
        else
          publish_to_error_queue(delivery_info, message_properties, message, reason, num_attempts)
        end
      end

      def publish_to_error_queue(delivery_info, message_properties, message, reason, num_attempts)
        Sneakers.logger.info do
          "#{log_prefix} message=failing, retry_count=#{num_attempts}, reason=#{reason}"
        end

        channel.basic_publish(
          error_payload(delivery_info, message_properties, message, reason, num_attempts),
          opts[:exchange],
          opts[:error_routing_key],
          content_type: 'application/json'
        )

        channel.acknowledge(delivery_info.delivery_tag)
      end

      def reject_to_retry(delivery_info, message_properties, num_attempts)
        Sneakers.logger.info do
          "#{log_prefix} msg=retrying, count=#{num_attempts}, headers=#{message_properties.headers}"
        end

        channel.reject(delivery_info.delivery_tag)
      end

      def error_payload(delivery_info, message_properties, payload, reason, num_attempts)
        {
          _error: {
            reason:             reason.to_s,
            num_attempts:       num_attempts,
            failed_at:          Time.now.iso8601,
            delivery_info:      delivery_info.to_hash,
            message_properties: message_properties.to_hash,
            payload:            payload.to_s
          }.merge!(exception_payload(reason))
        }.to_json
      end

      def exception_payload(reason)
        return {} unless reason.is_a?(Exception)

        {
          error_class:   reason.class.to_s,
          error_message: reason.to_s
        }.merge!(exception_backtrace(reason))
      end

      def exception_backtrace(reason)
        return {} unless reason.backtrace

        { backtrace: reason.backtrace.take(10).join(', ') }
      end

      def failure_count(headers)
        x_death_array = x_death_array(headers)

        return 0 if x_death_array.count == 0

        return x_death_array.count unless x_death_array.first['count']

        x_death_array.first['count'].to_i
      end

      def x_death_array(headers)
        return [] unless headers && headers['x-death']

        headers['x-death'].select do |x_death|
          x_death['queue'] == opts[:worker_queue_name]
        end
      end

      def log_prefix
        "#{self.class} handler [queue=#{opts[:worker_queue_name]}]"
      end

      def queue_durable?
        opts.fetch(:queue_options, {}).fetch(:durable, false)
      end
    end
  end
end
