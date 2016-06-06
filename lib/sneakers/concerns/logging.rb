module Sneakers
  module Concerns
    module Logging
      def self.included(base)
        base.extend ClassMethods
        base.send :define_method, :logger do
          base.logger
        end
      end

      module ClassMethods
        def logger
          @logger ||= configure_logger
        end

        def logger=(logger)
          @logger = logger
        end

        def configure_logger(log=nil)
          if log
            @logger = log
          else
            @logger = Logger.new(STDOUT)
            @logger.level = Logger::INFO
            @logger.formatter = Sneakers::Support::ProductionFormatter
          end
          @logger
        end
      end
    end
  end
end
