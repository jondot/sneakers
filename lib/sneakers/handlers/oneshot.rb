module Sneakers
  module Handlers
    class Oneshot
      def initialize(channel, queue, opts)
        @channel = channel
        @opts = opts
      end

      def acknowledge(hdr, props, msg)
        @channel.acknowledge(hdr.delivery_tag, false)
      end

      def reject(hdr, props, msg, requeue=false)
        @channel.reject(hdr.delivery_tag, requeue)
      end

      def error(hdr, props, msg, err)
        reject(hdr, props, msg)
      end

      def noop(hdr, props, msg)

      end
    end
  end
end
