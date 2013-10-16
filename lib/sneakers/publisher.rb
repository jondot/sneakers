require 'sneakers/support/queue_name'

module Sneakers
  class Publisher
    attr_accessor :exchange

    def initialize(opts={})
      @mutex = Mutex.new
      @opts = Sneakers::Config.merge(opts)
    end

    def publish(msg, routing)
      @mutex.synchronize do
        ensure_connection! unless connected?
      end
      Sneakers.logger.info("publishing <#{msg}> to [#{Support::QueueName.new(routing[:to_queue], @opts).to_s}]")
      @exchange.publish(msg, :routing_key => Support::QueueName.new(routing[:to_queue], @opts).to_s)
    end


  private

    def ensure_connection!
      @bunny = Bunny.new(:heartbeat => @opts[:heartbeat])
      @bunny.start
      @channel = @bunny.create_channel
      @exchange = @channel.exchange(@opts[:exchange], :type => :direct, :durable => @opts[:durable])
    end

    def connected?
      @bunny && @bunny.connected?
    end
  end
end

