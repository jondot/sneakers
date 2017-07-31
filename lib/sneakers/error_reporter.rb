# Ripped off from https://github.com/mperham/sidekiq/blob/master/lib/sidekiq/exception_handler.rb
module Sneakers
  module ErrorReporter
    class DefaultLogger
      def call(exception, worker, context_hash)
        Sneakers.logger.warn(context_hash) unless context_hash.empty?
        log_string = ''
        log_string += "[Exception error=#{exception.message.inspect} error_class=#{exception.class} worker_class=#{worker.class}"  unless exception.nil?
        log_string += " backtrace=#{exception.backtrace.take(50).join(',')}" unless exception.nil? || exception.backtrace.nil?
        log_string += ']'
        Sneakers.logger.error log_string
      end
    end

    def worker_error(exception, context_hash = {})
      Sneakers.error_reporters.each do |handler|
        begin
          handler.call(exception, self, context_hash)
        rescue => inner_exception
          Sneakers.logger.error '!!! ERROR REPORTER THREW AN ERROR !!!'
          Sneakers.logger.error inner_exception
          Sneakers.logger.error inner_exception.backtrace.join("\n") unless inner_exception.backtrace.nil?
        end
      end
    end
  end
end
