require 'sneakers/queue'
require 'sneakers/support/utils'
require 'timeout'

module Sneakers
  module Worker
    attr_reader :queue, :id, :opts

    # For now, a worker is hardly dependant on these concerns
    # (because it uses methods from them directly.)
    include Concerns::Logging
    include Concerns::Metrics

    def initialize(queue = nil, pool = nil, opts = {})
      opts = opts.merge(self.class.queue_opts || {})
      queue_name = self.class.queue_name
      opts = Sneakers::Config.merge(opts)

      @should_ack =  opts[:ack]
      @timeout_after = opts[:timeout_job_after]
      @pool = pool || Thread.pool(opts[:threads]) # XXX config threads
      @call_with_params = respond_to?(:work_with_params)

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

    def publish(msg, routing)
      return unless routing[:to_queue]
      @queue.exchange.publish(msg, :routing_key => routing[:to_queue])
    end

    def do_work(hdr, props, msg, handler)
      worker_trace "Working off: #{msg}"

      @pool.process do
        res = nil
        error = nil

        begin
          metrics.increment("work.#{self.class.name}.started")
          Timeout.timeout(@timeout_after) do
            metrics.timing("work.#{self.class.name}.time") do
              if @call_with_params
                res = work_with_params(msg, hdr, props)
              else
                res = work(msg)
              end
            end
          end
        rescue Timeout::Error
          res = :timeout
          logger.error("timeout")
        rescue => ex
          res = :error
          error = ex
          logger.error(ex)
        end

        if @should_ack
          if res == :ack
            # note to future-self. never acknowledge multiple (multiple=true) messages under threads.
            handler.acknowledge(hdr, props, msg)
          elsif res == :timeout
            handler.timeout(hdr, props, msg)
          elsif res == :error
            handler.error(hdr, props, msg, error)
          elsif res == :reject
            handler.reject(hdr, props, msg)
          elsif res == :requeue
            handler.reject(hdr, props, msg, true)
          else
            handler.noop(hdr, props, msg)
          end
          metrics.increment("work.#{self.class.name}.handled.#{res || 'reject'}")
        end

        metrics.increment("work.#{self.class.name}.ended")
      end #process
    end

    def stop
      worker_trace "Stopping worker: unsubscribing."
      @queue.unsubscribe
      worker_trace "Stopping worker: I'm gone."
    end

    def run
      worker_trace "New worker: subscribing."
      @queue.subscribe(self)
      worker_trace "New worker: I'm alive."
    end

    def worker_trace(msg)
      logger.debug "[#{@id}][#{Thread.current}][#{@queue.name}][#{@queue.opts}] #{msg}"
    end

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      attr_reader :queue_opts
      attr_reader :queue_name

      def from_queue(q, opts={})
        @queue_name = q.to_s
        @queue_opts = opts
      end

      def enqueue(msg)
        publisher.publish(msg, :to_queue => @queue_name)
      end

      private

      def publisher
        @publisher ||= Sneakers::Publisher.new
      end
    end
  end
end

