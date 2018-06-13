
class Sneakers::Queue
  attr_reader :name, :opts, :exchange, :channel

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
    # If we've already got a bunny object, use it.  This allows people to
    # specify all kinds of options we don't need to know about (e.g. for ssl).
    @bunny = @opts[:connection]
    @bunny ||= create_bunny_connection
    @bunny.start

    @channel = @bunny.create_channel
    @channel.prefetch(@opts[:prefetch])

    exchange_name = @opts[:exchange]
    @exchange = @channel.exchange(exchange_name, @opts[:exchange_options])

    routing_key = @opts[:routing_key] || @name
    routing_keys = [*routing_key]

    # TODO: get the arguments from the handler? Retry handler wants this so you
    # don't have to line up the queue's dead letter argument with the exchange
    # you'll create for retry.
    queue = @channel.queue(@name, @opts[:queue_options])

    if exchange_name.length > 0
      routing_keys.each do |key|
        if @opts[:bind_arguments]
          queue.bind(@exchange, routing_key: key, arguments: @opts[:bind_arguments])
        else
          queue.bind(@exchange, routing_key: key)
        end
      end
    end

    # NOTE: we are using the worker's options. This is necessary so the handler
    # has the same configuration as the worker. Also pass along the exchange and
    # queue in case the handler requires access to them (for things like binding
    # retry queues, etc).
    handler_klass = worker.opts[:handler] || Sneakers::CONFIG.fetch(:handler)
    handler = handler_klass.new(@channel, queue, worker.opts)

    @consumer = queue.subscribe(block: false, manual_ack: @opts[:ack]) do | delivery_info, metadata, msg |
      worker.do_work(delivery_info, metadata, msg, handler)
    end
    nil
  end

  def unsubscribe
    return unless @consumer

    # TODO: should we simply close the channel here?
    Sneakers.logger.info("Queue: will try to cancel consumer #{@consumer.inspect}")
    cancel_ok = @consumer.cancel
    if cancel_ok
      Sneakers.logger.info "Queue: consumer #{cancel_ok.consumer_tag} cancelled"
      @consumer = nil
    else
      Sneakers.logger.warn "Queue: could not cancel consumer #{@consumer.inspect}"
      sleep(1)
      unsubscribe
    end
  end

  def create_bunny_connection
    Bunny.new(@opts[:amqp], vhost: @opts[:vhost],
                            heartbeat: @opts[:heartbeat],
                            properties: @opts.fetch(:properties, {}),
                            logger: Sneakers::logger)
  end
  private :create_bunny_connection
end
