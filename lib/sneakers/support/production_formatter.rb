require 'time'
module Sneakers
  module Support
    class ProductionFormatter < Logger::Formatter
        def self.call(severity, time, program_name, message)
          "#{time.utc.iso8601} p-#{Process.pid} t-#{Thread.current.object_id.to_s(36)} #{severity}: #{message}\n"
        end
    end
  end
end

