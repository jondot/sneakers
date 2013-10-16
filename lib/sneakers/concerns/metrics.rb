require 'sneakers/metrics/null_metrics'

module Sneakers
  module Concerns
    module Metrics
      def self.included(base)
        base.extend ClassMethods
        base.send :define_method, :metrics do
          base.metrics
        end
      end

      module ClassMethods
        def metrics
          @metrics
        end

        def metrics=(metrics)
          @metrics = metrics
        end

        def configure_metrics(metrics=nil)
          if metrics
            @metrics = metrics
          else
            @metrics = Sneakers::Metrics::NullMetrics.new
          end
        end
      end
    end
  end
end


