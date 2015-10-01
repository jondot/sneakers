require 'spec_helper'
require 'sneakers'

describe Sneakers::Publisher do
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

      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should publish with the persistence specified' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads', persistence: true)

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)

      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads', persistence: true)
    end

    it 'should publish with arbitrary metadata specified' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads', expiration: 1, headers: {foo: 'bar'})

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)

      mock(p).ensure_connection! {}
      p.publish('test msg', to_queue: 'downloads', expiration: 1, headers: {foo: 'bar'})
    end

    it 'should not reconnect if already connected' do
      xchg = Object.new
      mock(xchg).publish('test msg', routing_key: 'downloads')

      p = Sneakers::Publisher.new
      p.instance_variable_set(:@exchange, xchg)

      mock(p).connected? { true }
      mock(p).ensure_connection!.times(0)

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
        durable: false)

      channel = Object.new
      mock(channel).exchange('another_exchange', type: :topic, durable: false, :auto_delete => false, arguments: { 'x-arg' => 'value' }) do
        mock(Object.new).publish('test msg', routing_key: 'downloads')
      end

      bunny = Object.new
      mock(bunny).start
      mock(bunny).create_channel { channel }

      mock(Bunny).new('amqp://someuser:somepassword@somehost:5672', heartbeat: 1, vhost: '/', logger: logger) { bunny }

      p = Sneakers::Publisher.new

      p.publish('test msg', to_queue: 'downloads')

    end
  end
end
