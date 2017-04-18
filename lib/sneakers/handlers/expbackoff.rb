require 'base64'
require 'json'

module Sneakers
  module Handlers
    #
    # Maxretry uses dead letter policies on Rabbitmq to requeue and retry
    # messages after failure (rejections, errors and timeouts). When the maximum
    # number of retries is reached it will put the message on an error queue.
    # This handler will only retry at the queue level. To accomplish that, the
    # setup is a bit complex.
    #
    # Input:
    #   worker_exchange (eXchange)
    #   worker_queue (Queue)
    # We create:
    #   worker_queue-retry - (X) where we setup the worker queue to dead-letter.
    #   worker_queue-retry - (Q) queue bound to ^ exchange, dead-letters to
    #                        worker_queue-retry-requeue.
    #   worker_queue-error - (X) where to send max-retry failures
    #   worker_queue-error - (Q) bound to worker_queue-error.
    #   worker_queue-retry-requeue - (X) exchange to bind worker_queue to for
    #                                requeuing directly to the worker_queue.
    #
    # This requires that you setup arguments to the worker queue to line up the
    # dead letter queue. See the example for more information.
    #
    # Many of these can be override with options:
    # - retry_exchange - sets retry exchange & queue
    # - retry_error_exchange - sets error exchange and queue
    # - retry_requeue_exchange - sets the exchange created to re-queue things
    #   back to the worker queue.
    #
    # initial_delay - 60 sec, etc
    # backoff_factor - 2, x2, x3, x4 etc
    #

    # - retry_backoff_base = 0, 30, 60, 120, 180, etc defaults to 0
    #

    class Expbackoff

      def initialize(channel, queue, opts)
        @worker_queue_name = queue.name
        Sneakers.logger.debug do
          "#{log_prefix} creating handler, opts=#{opts}"
        end

        @channel = channel
        @opts = opts

        # Construct names, defaulting where suitable
        retry_name = @opts[:retry_backoff_exchange] || "#{@worker_queue_name}-backoff"
        error_name = @opts[:retry_error_exchange] || "#{@worker_queue_name}-error"
        requeue_name = @opts[:retry_requeue_exchange] || "#{@worker_queue_name}-retry-requeue"
        retry_routing_key = @opts[:retry_routing_key] || "#"

        @max_retries = @opts[:retry_max_times] || 5
        @backoff_base = @opts[:retry_backoff_base] || 0

        # This is for example/dev/test
        @backoff_multiplier = @opts[:retry_backoff_multiplier] || 1000

        backoffs = Expbackoff.backoff_periods(@max_retries, @backoff_base)

        # Create the exchanges
        Sneakers.logger.debug { "#{log_prefix} creating exchange=#{retry_name}" }
        @retry_exchange = @channel.exchange(retry_name, :type => 'headers', :durable => exchange_durable?)
        @error_exchange, @requeue_exchange = [error_name, requeue_name].map do |name|
          Sneakers.logger.debug { "#{log_prefix} creating exchange=#{name}" }
          @channel.exchange(name,
                            :type => 'topic',
                            :durable => exchange_durable?)
        end

        backoffs.each do |bo|
          # Create the queues and bindings
          Sneakers.logger.debug do
            "#{log_prefix} creating queue=#{retry_name}-#{bo} x-dead-letter-exchange=#{requeue_name}"
          end
          retry_queue = @channel.queue("#{retry_name}-#{bo}",
                                       :durable => queue_durable?,
                                       :arguments => {
                                         :'x-dead-letter-exchange' => requeue_name,
                                         :'x-message-ttl' => bo * @backoff_multiplier
                                       })
          retry_queue.bind(@retry_exchange, :arguments => { :backoff => bo })
        end

        Sneakers.logger.debug do
          "#{log_prefix} creating queue=#{error_name}"
        end
        @error_queue = @channel.queue(error_name,
                                      :durable => queue_durable?)
        @error_queue.bind(@error_exchange, :routing_key => '#')

        # Finally, bind the worker queue to our requeue exchange
        queue.bind(@requeue_exchange, :routing_key => retry_routing_key)

      end

      def acknowledge(hdr, props, msg)
        @channel.acknowledge(hdr.delivery_tag, false)
      end

      def reject(hdr, props, msg, requeue = false)
        if requeue
          # This was explicitly rejected specifying it be requeued so we do not
          # want it to pass through our retry logic.
          @channel.reject(hdr.delivery_tag, requeue)
        else
          handle_retry(hdr, props, msg, :reject)
        end
      end


      def error(hdr, props, msg, err)
        handle_retry(hdr, props, msg, err)
      end

      def timeout(hdr, props, msg)
        handle_retry(hdr, props, msg, :timeout)
      end

      def noop(hdr, props, msg)

      end

      #####################################################
      # formula
      # base X = 0, 30, 60, 120, 180, etc defaults to 0
      # (X + 15) * 2 ** (count + 1)
      def self.backoff_periods(max_retries, backoff_base)
        (1..max_retries).map{ |c| next_ttl(c, backoff_base) }
      end

      def self.next_ttl(count, backoff_base)
        (backoff_base + 15) * 2 ** (count + 1)
      end

      #####################################################

      # Helper logic for retry handling. This will reject the message if there
      # are remaining retries left on it, otherwise it will publish it to the
      # error exchange along with the reason.
      # @param hdr [Bunny::DeliveryInfo]
      # @param props [Bunny::MessageProperties]
      # @param msg [String] The message
      # @param reason [String, Symbol, Exception] Reason for the retry, included
      #   in the JSON we put on the error exchange.
      def handle_retry(hdr, props, msg, reason)
        # +1 for the current attempt
        num_attempts = failure_count(props[:headers]) + 1
        if num_attempts <= @max_retries
          # We call reject which will route the message to the
          # x-dead-letter-exchange (ie. retry exchange) on the queue
          Sneakers.logger.info do
            "#{log_prefix} msg=retrying, count=#{num_attempts}, headers=#{props[:headers]}"
          end
          backoff_ttl = Expbackoff.next_ttl(num_attempts, @backoff_base)
          @retry_exchange.publish(msg, :routing_key => hdr.routing_key, :headers => { :backoff => backoff_ttl, :count => num_attempts })
          @channel.acknowledge(hdr.delivery_tag, false)
          # TODO: metrics
        else
          # Retried more than the max times
          # Publish the original message with the routing_key to the error exchange
          Sneakers.logger.info do
            "#{log_prefix} msg=failing, retry_count=#{num_attempts}, headers=#{props[:headers]}, reason=#{reason}"
          end
          data = {
            error: reason,
            num_attempts: num_attempts,
            failed_at: Time.now.iso8601,
            payload: Base64.encode64(msg.to_s),
            properties: Base64.encode64(props.to_json)
          }.tap do |hash|
            if reason.is_a?(Exception)
              hash[:error_class] = reason.class.to_s
              hash[:error_message] = "#{reason}"
              if reason.backtrace
                hash[:backtrace] = reason.backtrace.take(10).join(', ')
              end
            end
          end.to_json
          @error_exchange.publish(data, :routing_key => hdr.routing_key)
          @channel.acknowledge(hdr.delivery_tag, false)
          # TODO: metrics
        end
      end
      private :handle_retry

      # Uses the x-death header to determine the number of failures this job has
      # seen in the past. This does not count the current failure. So for
      # instance, the first time the job fails, this will return 0, the second
      # time, 1, etc.
      # @param headers [Hash] Hash of headers that Rabbit delivers as part of
      #   the message
      # @return [Integer] Count of number of failures.
      def failure_count(headers)
        if headers.nil? || headers['count'].nil?
          0
        else
          headers['count']
        end
      end
      private :failure_count

      # Prefix all of our log messages so they are easier to find. We don't have
      # the worker, so the next best thing is the queue name.
      def log_prefix
        "Expbackoff handler [queue=#{@worker_queue_name}]"
      end
      private :log_prefix

      private

      def queue_durable?
        @opts.fetch(:queue_options, {}).fetch(:durable, false)
      end

      def exchange_durable?
        queue_durable?
      end
    end
  end
end
