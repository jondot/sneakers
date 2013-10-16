module Sneakers
  module Handlers
    class Oneshot
      def initialize(channel)
        @channel = channel
      end

      def acknowledge(tag)
        @channel.acknowledge(tag, false)
      end

      def reject(tag, requeue=false)
        @channel.reject(tag, requeue)
      end

      def error(tag, err)
        reject(tag)
      end

      def timeout(tag)
        reject(tag)
      end

      def noop(tag)

      end
    end
  end
end
