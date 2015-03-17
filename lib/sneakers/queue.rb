
class Sneakers::Queue
  attr_reader :name, :opts, :exchange

  def initialize(name, opts)
    @name = name
    @opts = opts
    @handler_klass = Sneakers::CONFIG[:handler]
  end

  #
  # :exchange
  # :heartbeat_interval
  # :prefetch
  # :durable
  # :ack
  #
  def subscribe(worker)
    @bunny = Bunny.new(@opts[:amqp], :vhost => @opts[:vhost], :heartbeat => @opts[:heartbeat], :logger => Sneakers::logger)
    @bunny.start

    @channel = @bunny.create_channel
    @channel.prefetch(@opts[:prefetch])

    exchange_name = @opts[:exchange]
    @exchange = @channel.exchange(exchange_name,
                                  :type => @opts[:exchange_type],
                                  :durable => @opts[:durable])

    routing_key = @opts[:routing_key] || @name
    routing_keys = [*routing_key]

    # TODO: get the arguments from the handler? Retry handler wants this so you
    # don't have to line up the queue's dead letter argument with the exchange
    # you'll create for retry.
    queue_durable = @opts[:queue_durable].nil? ? @opts[:durable] : @opts[:queue_durable]
    queue = @channel.queue(@name, :durable => queue_durable, :arguments => @opts[:arguments])

    if exchange_name.length > 0
      routing_keys.each do |key|
        queue.bind(@exchange, :routing_key => key)
      end
    end

    # NOTE: we are using the worker's options. This is necessary so the handler
    # has the same configuration as the worker. Also pass along the exchange and
    # queue in case the handler requires access to them (for things like binding
    # retry queues, etc).
    handler_klass = worker.opts[:handler] || Sneakers::CONFIG[:handler]
    handler = handler_klass.new(@channel, queue, worker.opts)

    @consumer = queue.subscribe(:block => false, :manual_ack => @opts[:ack]) do | delivery_info, metadata, msg |
      worker.do_work(delivery_info, metadata, msg, handler)
    end
    nil
  end

  def unsubscribe
    # XXX can we cancel bunny and channel too?
    @consumer.cancel if @consumer
    @consumer = nil
  end
end
