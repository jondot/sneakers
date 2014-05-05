module Sneakers
  module Handlers
    #
    # Maxretry uses dead letter policies on Rabbitmq to requeue and retry
    # messages after failure (rejections, errors and timeouts). When the maximum
    # number of retries is reached it will put the message on an error queue.
    #
    class Maxretry

      def initialize(channel, opts)
        @channel = channel
        @opts = opts

        # If there is no retry exchange specified, use #{exchange}-retry
        retry_name = @opts[:retryexchange] || "#{@opts[:exchange]}-retry"

        # Create the retry exchange as a durable topic so we retain original routing keys but bind the queue using a wildcard
        retry_exchange = @channel.exchange( retry_name,
                                            :type => 'topic',
                                            :durable => 'true')

        # Create the retry queue with the same name as the retry exchange and a dead letter exchange
        # The dead letter exchange is the default exchange and the ttl can be from the opts or defaults to 60 seconds
        # TODO: respect @opts[:durable]? Are there cases where you want the
        # retry and error exchanges to match the originating exchange?
        retry_queue = @channel.queue( retry_name,
                                      :durable => 'true',
                                      :arguments => {
                                        :'x-dead-letter-exchange' => @opts[:exchange],
                                        :'x-message-ttl' => @opts[:retry_timeout] || 60000
                                    })

        # Bind the retry queue to the retry topic exchange with a wildcard
        retry_queue.bind(retry_exchange, :routing_key => '#')

        ## Setup the error queue

        # If there is no error exchange specified, use #{exchange}-error
        error_name = @opts[:errorexchange] || "#{@opts[:exchange]}-error"

        # Create the error exchange as a durable topic so we retain original routing keys but bind the queue using a wildcard
        @error_exchange = @channel.exchange(error_name,
                                            :type => 'topic',
                                            :durable => 'true')

        # Create the error queue with the same name as the error exchange
        error_queue = @channel.queue( error_name,
                                      :durable => 'true')

        # Bind the error queue to the error topic exchange with a wildcard
        error_queue.bind(@error_exchange, :routing_key => '#')

        @max_retries = @opts[:retry_max_times] || 5

      end

      def acknowledge(hdr, props, msg)
        @channel.acknowledge(hdr.delivery_tag, false)
      end

      def reject(hdr, props, msg, requeue=false)

        # Note to readers, the count of the x-death will increment by 2 for each
        # retry, once for the reject and once for the expiration from the retry
        # queue
        if requeue || ((failure_count(props[:headers]) + 1) < @max_retries)
          # We call reject which will route the message to the x-dead-letter-exchange (ie. retry exchange) on the queue
          @channel.reject(hdr.delivery_tag, requeue)
          # TODO: metrics
        else
          # Retried more than the max times
          # Publish the original message with the routing_key to the error exchange
          @error_exchange.publish(msg, :routing_key => hdr.routing_key)
          @channel.acknowledge(hdr.delivery_tag, false)
          # TODO: metrics
        end
      end

      def error(hdr, props, msg, err)
        reject(hdr, props, msg)
      end

      def timeout(hdr, props, msg)
        reject(hdr, props, msg)
      end

      def noop(hdr, props, msg)

      end

      # Uses the x-death header to determine the number of failures this job has
      # seen in the past. This does not count the current failure. So for
      # instance, the first time the job fails, this will return 0, the second
      # time, 1, etc.
      # @param headers [Hash] Hash of headers that Rabbit delivers as part of
      #   the message
      # @return [Integer] Count of number of failures.
      def failure_count(headers)
        if headers.nil? || headers['x-death'].nil?
          0
        else
          headers['x-death'].select do |x_death|
            x_death['queue'] == @opts[:exchange]
          end.count
        end
      end
      private :failure_count
    end
  end
end
