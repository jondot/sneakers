require 'sneakers/queue'
require 'sneakers/support/utils'

module Sneakers
  module Worker
    attr_reader :queue, :id, :opts

    # For now, a worker is hardly dependant on these concerns
    # (because it uses methods from them directly.)
    include Concerns::Logging
    include Concerns::Metrics
    include Sneakers::ErrorReporter

    def initialize(queue = nil, pool = nil, opts = {})
      opts = opts.merge(self.class.queue_opts || {})
      queue_name = self.class.queue_name
      opts = Sneakers::CONFIG.merge(opts)

      @should_ack =  opts[:consumer_options][:manual_ack]
      @pool = pool || Concurrent::FixedThreadPool.new(opts[:threads] || Sneakers::Configuration::DEFAULTS[:threads])
      @call_with_params = respond_to?(:work_with_params)
      @content_type = opts[:content_type]

      @queue = queue || Sneakers::Queue.new(
        queue_name,
        opts
      )

      @opts = opts
      @id = Utils.make_worker_id(queue_name)
    end

    def ack!; :ack end
    def reject!; :reject; end
    def requeue!; :requeue; end

    def publish(msg, opts)
      to_queue = opts.delete(:to_queue)
      opts[:routing_key] ||= to_queue
      return unless opts[:routing_key]
      @queue.exchange.publish(Sneakers::ContentType.serialize(msg, opts[:content_type]), opts)
    end

    def do_work(delivery_info, metadata, msg, handler)
      worker_trace "Working off: #{msg.inspect}"

      @pool.post do
        process_work(delivery_info, metadata, msg, handler)
      end
    end

    def process_work(delivery_info, metadata, msg, handler)
      res = nil
      error = nil

      begin
        metrics.increment("work.#{self.class.name}.started")
        metrics.timing("work.#{self.class.name}.time") do
          deserialized_msg = ContentType.deserialize(msg, @content_type || metadata && metadata[:content_type])

          app = -> (deserialized_msg, delivery_info, metadata, handler) do
            if @call_with_params
              work_with_params(deserialized_msg, delivery_info, metadata)
            else
              work(deserialized_msg)
            end
          end

          middlewares = Sneakers.middleware.to_a
          block_to_call = middlewares.reverse.reduce(app) do |mem, h|
            h[:class].new(mem, *h[:args])
          end
          res = block_to_call.call(deserialized_msg, delivery_info, metadata, handler)
        end
      rescue SignalException, SystemExit
        # ServerEngine handles these exceptions, so they are not expected to be raised within the worker.
        # Nevertheless, they are listed here to ensure that they are not caught by the rescue block below.
        raise
      rescue Exception => ex
        res = :error
        error = ex
        worker_error(ex, log_msg: log_msg(msg), class: self.class.name,
                     message: msg, delivery_info: delivery_info, metadata: metadata)
      ensure
        if @should_ack
          case res
          # note to future-self. never acknowledge multiple (multiple=true) messages under threads.
          when :ack then handler.acknowledge(delivery_info, metadata, msg)
          when :error then handler.error(delivery_info, metadata, msg, error)
          when :reject then handler.reject(delivery_info, metadata, msg)
          when :requeue then handler.reject(delivery_info, metadata, msg, true)
          else
            handler.noop(delivery_info, metadata, msg)
          end
          metrics.increment("work.#{self.class.name}.handled.#{res || 'noop'}")
        end

        metrics.increment("work.#{self.class.name}.ended")
      end
    end

    def stop
      worker_trace "Stopping worker: unsubscribing."
      @queue.unsubscribe
      worker_trace "Stopping worker: shutting down thread pool."
      @pool.shutdown
      @pool.wait_for_termination
      worker_trace "Stopping worker: I'm gone."
    end

    def run
      worker_trace "New worker: subscribing."
      @queue.subscribe(self)
      worker_trace "New worker: I'm alive."
    end

    # Construct a log message with some standard prefix for this worker
    def log_msg(msg)
      "[#{@id}][#{Thread.current}][#{@queue.name}][#{@queue.opts}] #{msg}"
    end

    def worker_trace(msg)
      logger.debug(log_msg(msg))
    end

    Classes = []

    def self.included(base)
      base.extend ClassMethods
      Classes << base if base.is_a? Class
    end

    module ClassMethods
      attr_reader :queue_opts
      attr_reader :queue_name

      def from_queue(q, opts={})
        @queue_name = q.to_s
        @queue_opts = opts
      end

      def enqueue(msg, opts={})
        opts[:routing_key] ||= @queue_opts[:routing_key]
        opts[:content_type] ||= @queue_opts[:content_type]
        opts[:to_queue] ||= @queue_name

        publisher.publish(msg, opts)
      end

      private

      def publisher
        @publisher ||= Sneakers::Publisher.new(queue_opts)
      end
    end
  end
end
