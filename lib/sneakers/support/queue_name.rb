module Sneakers
  module Support
    class QueueName
      def initialize(queue, opts)
        @queue = queue
        @opts = opts
      end

      def to_s
        [@queue, @opts[:env]].compact.join('_')
      end
    end
  end
end
