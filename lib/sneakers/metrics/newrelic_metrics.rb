module Sneakers
  module Metrics
    class NewrelicMetrics

      def self.eagent(eagent = nil)
        @eagent = eagent || @eagent
      end

      def initialize()
        #@connection = conn
      end

      def increment(metric)
        record_stat metric, 1
      end

      def record_stat(metric, num)
        metric_name = "Custom/#{metric.gsub("\.", "\/")}"
        NewrelicMetrics.eagent::Agent.record_metric(metric_name, num)
      rescue Exception => e
        puts "NewrelicMetrics#record_stat: #{e}"
      end

      def timing(metric, &block)
        start = Time.now
        block.call
        record_stat(metric, ((Time.now - start)*1000).floor)
      end
    end
  end
end

