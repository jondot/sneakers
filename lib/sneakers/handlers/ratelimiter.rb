module Sneakers
  module Handlers
    class RateLimiter
      def initialize(channel, queue, opts)
        @channel = channel
        @handler = (opts[:rate_limiter_decorated_handler_func] && opts[:rate_limiter_decorated_handler_func].call(channel, queue, opts)) || Sneakers::Handlers::Oneshot.new(channel, queue, opts)
        @worker_exchange_name = opts[:exchange] || 'sneakers'
        overflow_queue_timeout = opts[:overflow_timeout] || 10_000
        rate_limit_queue_timeout = opts[:rate_limit_timeout] || 5000
        rate_limit_queue_size = opts[:rate_limit_length] || 1


        @worker_queue_name = queue.name
        @worker_exchange = @channel.exchange(opts[:exchange], opts[:exchange_options])

        # Construct names
        @rate_limit_exchange_name = "rate_limit"
        @overflow_queue_name = "#{@worker_queue_name}-overflow"
        @rate_limit_queue_name = "#{@worker_queue_name}-rate_limit"

        # Create exchange
        @rate_limit_exchange = @channel.exchange(@rate_limit_exchange_name,
                                  :type => 'direct',
                                  :durable => true)

        # Create the queues

        @overflow_queue = @channel.queue(@overflow_queue_name,
                                      :durable => true,
                                      :arguments => {
                                        :'x-dead-letter-exchange' => @worker_exchange_name,
                                        :'x-dead-letter-routing-key' => @worker_queue_name,
                                        :'x-message-ttl' => overflow_queue_timeout
                                      })

        @rate_limit_queue = @channel.queue(@rate_limit_queue_name,
                                         :durable => true,
                                         :arguments => {
                                           :'x-dead-letter-exchange' => @worker_exchange_name,
                                           :'x-dead-letter-routing-key' =>	@worker_queue_name,
                                           :'x-message-ttl' => rate_limit_queue_timeout,
                                           :'x-max-length' => rate_limit_queue_size,
                                           :'x-overflow' => 'reject-publish'
                                         })

        # Create bindings
        @rate_limit_queue.bind(@rate_limit_exchange, :routing_key => @worker_queue_name)
        @overflow_queue.bind(@rate_limit_exchange, :routing_key => @overflow_queue_name)
      end

      def acknowledge(*args)
        Sneakers.logger.debug { "rate_limiter acknowledge #{@handler.inspect}" }
        @handler.acknowledge(*args)
      end

      def reject(hdr, props, msg, requeue=false)
        @handler.reject(hdr, props, msg, requeue)
      end

      def error(hdr, props, msg, err)
        @handler.error(hdr, props, msg, err)
      end

      def noop(*args)
        @handler.noop(*args)
      end

      def before_work(hdr, props, msg)
        return true if message_went_through_rate_limit_queue?(props[:headers])

        send_to_overflow_queue(msg, props[:headers]) unless send_to_rate_limit_queue(msg, props[:headers])

        acknowledge(hdr, props, msg)
        return false
      end

      def message_went_through_rate_limit_queue?(headers)
        return false if headers.nil? || headers['x-death'].nil?
        headers['x-death'].any? {|x_death| x_death['exchange'] == @rate_limit_exchange_name && x_death['queue'] == @rate_limit_queue_name}
      end

      private

      def send_to_rate_limit_queue(msg, headers)
        @channel.confirm_select
        @rate_limit_exchange.publish(msg, :headers => headers, :routing_key => @worker_queue_name)
        success = @channel.wait_for_confirms
        if success
          Sneakers.logger.debug { "send_to_rate_limit_queue success" }
          return true
        else
          Sneakers.logger.debug { "send_to_rate_limit_queue fail" }
          return false
        end
      end

      def send_to_overflow_queue(msg, headers)
        Sneakers.logger.debug { "send_to_overflow_queue" }
        @rate_limit_exchange.publish(msg, :headers => headers, :routing_key => @overflow_queue_name)
      end
    end
  end
end
