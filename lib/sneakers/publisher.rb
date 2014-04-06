module Sneakers
  class Publisher
    def initialize(opts = {})
      @mutex = Mutex.new
      @opts = Sneakers::Config.merge(opts)
    end

    def publish(msg, routing)
      @mutex.synchronize do
        ensure_connection! unless connected?
      end
      Sneakers.logger.info("publishing <#{msg}> to [#{routing[:to_queue]}]")
      @exchange.publish(msg, routing_key: routing[:to_queue], persistence: routing[:persistence])
    end

    private

    attr_reader :exchange

    def ensure_connection!
      @bunny = Bunny.new(@opts[:amqp], heartbeat: @opts[:heartbeat])
      @bunny.start
      @channel = @bunny.create_channel
      @exchange = @channel.exchange(@opts[:exchange], type: @opts[:exchange_type], durable: @opts[:durable])
    end

    def connected?
      @bunny && @bunny.connected?
    end
  end
end

