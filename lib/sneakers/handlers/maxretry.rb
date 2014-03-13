module Sneakers
  module Handlers
    class Maxretry
      
      ###
      # Maxretry uses dead letter policies on Rabbitmq to requeue and retry messages after a timeout
      # 
      ###

      def initialize(channel)
        @channel = channel
      end

      def acknowledge(tag)
        @channel.acknowledge(tag, false)
      end

      def reject(tag, props, msg, requeue=false)
        # Check how many times it has been requeued
        if props[:headers].nil? or props[:headers]['x-death'].nil? or props[:headers]['x-death'].count < 5
          @channel.reject(tag, requeue)
        else
        # Retried more than the max times
          @exchange.publish({:msg => msg, :routing_key => rops[:headers]['routing-keys'][0]}.to_json, :routing_key => 'error')
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
