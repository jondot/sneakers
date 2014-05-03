
class Sneakers::Queue
  attr_reader :name, :opts, :exchange

  def initialize(name, opts)
    @name = name
    @opts = opts
    @handler_klass = Sneakers::Config[:handler]
  end

  #
  # :exchange
  # :heartbeat_interval
  # :prefetch
  # :durable
  # :ack
  #
  def subscribe(worker)
    @bunny = Bunny.new(@opts[:amqp], :vhost => @opts[:vhost], :heartbeat => @opts[:heartbeat])
    @bunny.start

    @channel = @bunny.create_channel
    @channel.prefetch(@opts[:prefetch])

    @exchange = @channel.exchange(@opts[:exchange],
                                  :type => @opts[:exchange_type],
                                  :durable => @opts[:durable])

    handler = @handler_klass.new(@channel, @opts)

    routing_key = @opts[:routing_key] || @name
    routing_keys = [*routing_key]

    queue = @channel.queue(@name, :durable => @opts[:durable], :arguments => @opts[:arguments])

    routing_keys.each do |key|
      queue.bind(@exchange, :routing_key => key)
    end

    @consumer = queue.subscribe(:block => false, :ack => @opts[:ack]) do | hdr, props, msg | 
      worker.do_work(hdr, props, msg, handler)
    end
    nil
  end

  def unsubscribe
    # XXX can we cancel bunny and channel too?
    @consumer.cancel if @consumer
    @consumer = nil
  end
end
