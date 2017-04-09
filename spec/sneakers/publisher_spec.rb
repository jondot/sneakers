require 'spec_helper'
require 'sneakers'

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
    let(:logger) { Logger.new('/dev/null') }

    before do
      Sneakers.clear!
      Sneakers.configure(:log => 'sneakers.log')
    end

    it 'should publish a message to an exchange' do
      bunny = Object.new
      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(bunny).connected? { false }
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('sneakers', { type: :direct, durable: true, auto_delete: false, arguments: {}}) { exchange }
      mock(exchange).publish('test msg', routing_key: 'downloads')
      mock(p).ensure_connection! {}

      p.instance_variable_set(:@bunny, bunny)
      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should publish with the persistence specified' do
      bunny = Object.new
      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(bunny).connected? { false }
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('sneakers', { type: :direct, durable: true, auto_delete: false, arguments: {}}) { exchange }
      mock(exchange).publish('test msg', routing_key: 'downloads', persistence: true)
      mock(p).ensure_connection! {}

      p.instance_variable_set(:@bunny, bunny)
      p.publish('test msg', to_queue: 'downloads', persistence: true)
    end

    it 'should publish with arbitrary metadata specified' do
      bunny = Object.new
      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(bunny).connected? { false }
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('sneakers', { type: :direct, durable: true, auto_delete: false, arguments: {}}) { exchange }
      mock(exchange).publish('test msg', routing_key: 'downloads', expiration: 1, headers: {foo: 'bar'})
      mock(p).ensure_connection! {}

      p.instance_variable_set(:@bunny, bunny)
      p.publish('test msg', to_queue: 'downloads', expiration: 1, headers: {foo: 'bar'})
    end

    it 'should not reconnect if already connected' do
      bunny = Object.new
      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(p).connected? { true }
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('sneakers', { type: :direct, durable: true, auto_delete: false, arguments: {}}) { exchange }
      mock(exchange).publish('test msg', routing_key: 'downloads')
      mock(p).ensure_connection!.times(0)

      p.instance_variable_set(:@bunny, bunny)
      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should connect to rabbitmq configured on Sneakers.configure' do
      exchange_opts = { :type => :topic, :arguments => { 'x-arg' => 'value' } }

      Sneakers.configure(
        amqp: 'amqp://someuser:somepassword@somehost:5672',
        heartbeat: 1,
        exchange: 'another_exchange',
        exchange_options: exchange_opts,
        log: logger,
        durable: false
      )

      bunny = Object.new
      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(bunny).start
      mock(bunny).connected? { false }
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('another_exchange', exchange_opts.merge(durable: false, auto_delete: false)) { exchange }
      mock(exchange).publish('test msg', routing_key: 'downloads')
      mock(Bunny).new('amqp://someuser:somepassword@somehost:5672', heartbeat: 1, vhost: '/', logger: logger) { bunny }

      p.instance_variable_set(:@bunny, bunny)
      p.publish('test msg', to_queue: 'downloads')
    end

    it 'should use an externally instantiated bunny session if provided' do
      bunny = Object.new
      exchange_opts = { :type => :topic, :arguments => { 'x-arg' => 'value' } }

      Sneakers.configure(
        connection: bunny,
        heartbeat: 1,
        exchange: 'yet_another_exchange',
        exchange_type: exchange_opts[:type],
        exchange_arguments: exchange_opts[:arguments],
        log: logger,
        durable: false
      )

      channel = Object.new
      exchange = Object.new
      p = Sneakers::Publisher.new

      mock(bunny).start
      mock(bunny).with_channel.yields(channel) { channel }
      mock(channel).exchange('yet_another_exchange', exchange_opts.merge(durable: false, auto_delete: false)) { exchange }
      mock(exchange).publish('test msg', pub_vars.merge(routing_key: 'downloads'))

      p.publish('test msg', pub_vars.merge(to_queue: 'downloads'))
      p.instance_variable_get(:@bunny).must_equal bunny
    end
  end
end
