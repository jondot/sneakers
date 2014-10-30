
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
  # :manual_ack
  #
  def connect(worker)
    @bunny = Bunny.new(@opts[:amqp], :vhost => @opts[:vhost], :heartbeat => @opts[:heartbeat], :logger => Sneakers::logger)
    @bunny.start

    @channel = @bunny.create_channel
    @channel.prefetch(@opts[:prefetch])

    @exchange = @channel.exchange(@opts[:exchange],
                                  :type => @opts[:exchange_type],
                                  :durable => @opts[:durable])

    @handler = @handler_klass.new(@channel)

    routing_key = @opts[:routing_key] || @name
    routing_keys = [*routing_key]

    @queue = @channel.queue(@name, :durable => @opts[:durable], :arguments => @opts[:arguments])

    routing_keys.each do |key|
      @queue.bind(@exchange, :routing_key => key)
    end

    nil
  end

  def subscribe(worker)
    connect(worker)
    @consumer = @queue.subscribe(:block => false, :ack => @opts[:ack]) do | delivery_info, metadata, msg |
      worker.do_work(delivery_info, metadata, msg, @handler)
    end
  end

  def pop(worker)
    connect(worker)
    delivery_info, metadata, msg = @queue.pop(:block => true, :manual_ack => true)
    worker.do_work(delivery_info, metadata, msg, @handler)
  end

  def unsubscribe
    # XXX can we cancel bunny and channel too?
    @consumer.cancel if @consumer
    @consumer = nil
  end
end
