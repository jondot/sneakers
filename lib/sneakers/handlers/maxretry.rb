module Sneakers
  module Handlers
    class Maxretry
      
      ###
      # Maxretry uses dead letter policies on Rabbitmq to requeue and retry messages after a timeout
      # 
      ###

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

        # Create the error queue with the same name as the error exchange and a dead letter exchange
        # The dead letter exchange is the default exchange and the ttl can be from the opts or defaults to 60 seconds
        error_queue = @channel.queue( error_name,
                                      :durable => 'true')

        # Bind the error queue to the error topic exchange with a wildcard
        error_queue.bind(@error_exchange, :routing_key => '#')

      end

      def acknowledge(hdr)
        @channel.acknowledge(hdr.delivery_tag, false)
      end

      def reject(hdr, props, msg, requeue=false)
        
        # Note to readers, the count of the x-death will increment by 2 for each retry, once for the reject and once for the expiration from the retry queue
        if props[:headers].nil? or props[:headers]['x-death'].nil? or props[:headers]['x-death'].count < 5
          # We call reject which will route the message to the x-dead-letter-exchange (ie. retry exchange) on the queue
          @channel.reject(hdr.delivery_tag, requeue)
        
        else
          # Retried more than the max times
          # Publish the original message with the routing_key to the error exchange
          @error_exchange.publish(msg, :routing_key => hdr.routing_key)
          @channel.acknowledge(hdr.delivery_tag, false)
          
        end
      end

      def error(hdr, props, msg, err)
        reject(hdr.delivery_tag, props, msg)
      end

      def timeout(hdr, props, msg)
        reject(hdr.delivery_tag, props, msg)
      end

      def noop(hdr)

      end
    end
  end
end
