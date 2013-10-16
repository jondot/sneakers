module Sneakers
  module Metrics
    class LoggingMetrics
      def increment(metric)
        Sneakers.logger.info("INC: #{metric}")
      end

      def timing(metric, &block)
        start = Time.now
        block.call
        Sneakers.logger.info("TIME: #{metric} #{Time.now - start}")
      end
    end
  end
end

