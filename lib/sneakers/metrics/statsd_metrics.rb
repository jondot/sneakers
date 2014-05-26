module Sneakers
  module Metrics
    class StatsdMetrics
      def initialize(conn)
        @connection = conn
      end

      def increment(metric)
        @connection.increment(metric)
      end

      def timing(metric, &block)
        start = Time.now
        block.call
        @connection.timing(metric, ((Time.now - start)*1000).floor)
      end

    end
  end
end

