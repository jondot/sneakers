require 'spec_helper'
require 'sneakers'
require 'serverengine'

describe Sneakers::Publisher do
  let :pub_vars do
    {
      :prefetch => 25,
      :durable => true,
      :ack => true,
      :heartbeat => 2,
      :vhost => '/',
      :exchange => "sneakers",
      :exchange_type => :direct,
      :exchange_arguments => { 'x-arg' => 'value' }
    }
  end

  describe '#publish' do
    before do
      Sneakers.clear!
      Sneakers.configure(:log => 'sneakers.log')
    end

    it 'should publish a message to an exchange' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@queue, xchg)

      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should publish with the persistence specified' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads', persistence: true)

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@queue, xchg)

      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads', persistence: true)
    end

    it 'should publish with arbitrary metadata specified' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads', expiration: 1, headers: {foo: 'bar'})

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@queue, xchg)
 
      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads', expiration: 1, headers: {foo: 'bar'})
    end

    it 'should not reconnect if already connected' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@queue, xchg)

      mock(p).connected? { true }
      mock(p).ensure_connection!.times(0)

      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should create the queue by default' do
      xchg = Object.new
      channel = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@channel, channel)

      mock(p).ensure_connection!
      mock(channel).queue("downloads", {:durable=>true, :auto_delete=>false, :exclusive=>false, :arguments=>{}})
      mock(p.instance_variable_get(:@queue)).bind(xchg, routing_key: "downloads")

      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should not create queue if queue instance already set' do
      xchg = Object.new
      channel = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)
      p.instance_variable_set(:@queue, xchg)
      p.instance_variable_set(:@channel, channel)

      mock(p).ensure_connection!
      mock(channel).queue.times(0)

      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should connect to rabbitmq configured on Sneakers.configure' do
      logger = Logger.new('/dev/null')
      Sneakers.configure(
        amqp: 'amqp://someuser:somepassword@somehost:5672',
        heartbeat: 1,
        exchange: 'another_exchange',
        exchange_options: { :type => :topic, :arguments => { 'x-arg' => 'value' } },
        log: logger,
        properties: { key: "value" },
        durable: false)

      channel = Object.new
      mock(channel).exchange('another_exchange', type: :topic, durable: false, :auto_delete => false, arguments: { 'x-arg' => 'value' }) do
        mock(Object.new).publish('test msg', routing_key: 'downloads')
      end

      bunny = Object.new
      queue = Object.new
      mock(bunny).start
      mock(bunny).create_channel { channel }

      mock(Bunny).new('amqp://someuser:somepassword@somehost:5672', heartbeat: 1, vhost: '/', logger: logger, properties: { key: "value" }) { bunny }

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@queue, queue)

      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should use an externally instantiated bunny session if provided' do
      logger = Logger.new('/dev/null')
      channel = Object.new
      exchange = Object.new
      queue = Object.new
      existing_session = Bunny.new
      my_vars = pub_vars.merge(to_queue: 'downloads')

      mock(existing_session).start
      mock(existing_session).create_channel { channel }

      mock(channel).exchange('another_exchange', type: :topic, durable: false, :auto_delete => false, arguments: { 'x-arg' => 'value' }) do
        exchange
      end

      mock(exchange).publish('test msg', my_vars)

      Sneakers.configure(
        connection: existing_session,
        heartbeat: 1, exchange: 'another_exchange',
        exchange_type: :topic,
        exchange_arguments: { 'x-arg' => 'value' },
        log: logger,
        durable: false
      )

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@queue, queue)
      p.publish('test msg', my_vars)
      p.instance_variable_get(:@bunny).must_equal existing_session
    end

    it 'should publish using the content type serializer' do
      Sneakers::ContentType.register(
        content_type: 'application/json',
        serializer: ->(payload) { JSON.dump(payload) },
        deserializer: ->(_) {},
      )

      xchg = Object.new
      mock(xchg).publish('{"foo":"bar"}', routing_key: 'downloads', content_type: 'application/json')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)

      mock(p).ensure_connection! {}
      p.publish({ 'foo' => 'bar' }, to_queue: 'downloads', content_type: 'application/json')

      Sneakers::ContentType.reset!
    end
  end
end
