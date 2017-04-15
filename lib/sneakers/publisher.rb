module Sneakers
  class Publisher
    def initialize(opts = {})
      @mutex = Mutex.new
      @opts = Sneakers::CONFIG.merge(opts)
    end

    def publish(msg, options = {})
      @mutex.synchronize do
        ensure_connection! unless connected?
      end
      to_queue = options.delete(:to_queue)
      options[:routing_key] ||= to_queue
      Sneakers.logger.info {"publishing <#{msg}> to [#{options[:routing_key]}]"}
      @exchange.publish(ContentType.serialize(msg, options[:content_type]), options)
    end


    attr_reader :exchange

  private
    def ensure_connection!
      # If we've already got a bunny object, use it.  This allows people to
      # specify all kinds of options we don't need to know about (e.g. for ssl).
      @bunny = @opts[:connection]
      @bunny ||= create_bunny_connection
      @bunny.start
      @channel = @bunny.create_channel
      @exchange = @channel.exchange(@opts[:exchange], @opts[:exchange_options])
    end

    def connected?
      @bunny && @bunny.connected?
    end

    def create_bunny_connection
      Bunny.new(@opts[:amqp], :vhost => @opts[:vhost],
                              :heartbeat => @opts[:heartbeat],
                              :properties => @opts.fetch(:properties, {}),
                              :logger => Sneakers::logger)
    end
  end
end
