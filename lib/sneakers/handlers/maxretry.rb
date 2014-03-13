module Sneakers
  module Handlers
    class Maxretry
      
      ###
      # Maxretry uses dead letter policies on Rabbitmq to requeue and retry messages after a timeout
      # 
      ###

      def initialize(channel)
        @channel = channel

        # We need to setup the sneakers-retry exchange and queue
        retry_exchange = @channel.exchange('sneakers-retry',
                                  :type => 'fanout',
                                  :durable => 'true')
        retry_queue = @channel.queue('sneakers-retry',
                                  :durable => 'true',
                                  :arguments => {
                                    :'x-dead-letter-exchange' => 'sneakers',
                                    :'x-message-ttl' => 10000
                                  })
        retry_queue.bind(retry_exchange)

      end

      def acknowledge(tag)
        @channel.acknowledge(tag, false)
      end

      def reject(tag, props, msg, requeue=false)
        # Check how many times it has been requeued
        puts "Got xdeath #{props.inspect}"  

        if props[:headers].nil? or props[:headers]['x-death'].nil? or props[:headers]['x-death'].count < 5
          puts "Retrying"
          @channel.reject(tag, requeue)
        else
        # Retried more than the max times
          puts "Publishing to error queue"
          #@exchange.publish({:msg => msg, :routing_key => rops[:headers]['routing-keys'][0]}.to_json, :routing_key => 'error')
          @channel.acknowledge(tag, false)
        end
      end

      def error(tag, props, msg, err)
        reject(tag, props, msg)
      end

      def timeout(tag, props, msg)
        reject(tag, props, msg)
      end

      def noop(tag)

      end
    end
  end
end
