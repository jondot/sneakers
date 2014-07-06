module Sneakers
  class Publisher
    def initialize(opts = {})
      @mutex = Mutex.new
      @opts = Sneakers::Config.merge(opts)
    end

    def publish(msg, options = {})
      @mutex.synchronize do
        ensure_connection! unless connected?
      end
      to_queue = options.delete(:to_queue)
      options[:routing_key] ||= to_queue
      Sneakers.logger.info {"publishing <#{msg}> to [#{options[:routing_key]}]"}
      @exchange.publish(msg, options)
    end

    private

    attr_reader :exchange

    def ensure_connection!
      @bunny = Bunny.new(@opts[:amqp], heartbeat: @opts[:heartbeat], vhost: @opts[:vhost])
      @bunny.start
      @channel = @bunny.create_channel
      @exchange = @channel.exchange(@opts[:exchange], type: @opts[:exchange_type], durable: @opts[:durable])
    end

    def connected?
      @bunny && @bunny.connected?
    end
  end
end

