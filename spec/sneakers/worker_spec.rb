require 'spec_helper'
require 'sneakers'
require 'serverengine'

class DummyWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :exchange_options => {
               :type => :topic,
               :durable => false,
               :auto_delete => true,
               :arguments => { 'x-arg' => 'value' }
             },
             :queue_options => {
               :durable => false,
               :auto_delete => true,
               :exclusive => true,
               :arguments => { 'x-arg' => 'value' }
             },
             :ack => false,
             :threads => 50,
             :prefetch => 40,
             :exchange => 'dummy',
             :heartbeat => 5

  def work(msg)
  end
end

class DefaultsWorker
  include Sneakers::Worker
  from_queue 'defaults'

  def work(msg)
  end
end

class AcksWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true

  def work(msg)
    if msg == :ack
      ack!
    elsif msg == :nack
      nack!
    elsif msg == :reject
      reject!
    else
      msg
    end
  end
end

class PublishingWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => false,
             :exchange => 'foochange'

  def work(msg)
    publish msg, :to_queue => 'target'
  end
end

class JSONPublishingWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => false,
             :exchange => 'foochange'

  def work(msg)
    publish msg, :to_queue => 'target', :content_type => 'application/json'
  end
end

class LoggingWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => false

  def work(msg)
    logger.info "hello"
  end
end

class JSONWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => false,
             :content_type => 'application/json'

  def work(msg)
  end
end

class MetricsWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true

  def work(msg)
    metrics.increment "foobar"
    msg
  end
end

class WithParamsWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true

  def work_with_params(msg, delivery_info, metadata)
    msg
  end
end

class WithDeprecatedExchangeOptionsWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :durable => false,
             :exchange_type => :topic,
             :exchange_arguments => { 'x-arg' => 'value' },
             :arguments => { 'x-arg2' => 'value2' }

  def work(msg)
  end
end

TestPool ||= Concurrent::ImmediateExecutor

describe Sneakers::Worker do
  before do
    @queue = Object.new
    @exchange = Object.new
    stub(@queue).name { 'test-queue' }
    stub(@queue).opts { {} }
    stub(@queue).exchange { @exchange }

    Sneakers.clear!
    Sneakers.configure(daemonize: true, log: 'sneakers.log')
    Sneakers::Worker.configure_metrics
  end

  describe ".enqueue" do
    it "publishes a message to the class queue" do
      message = 'test message'

      mock(Sneakers::Publisher).new(DummyWorker.queue_opts) do
        mock(Object.new).publish(message, {
          :routing_key => 'test.routing.key',
          :to_queue    => 'downloads',
          :content_type => nil,
        })
      end

      DummyWorker.enqueue(message, :routing_key => 'test.routing.key')
    end
  end

  describe "#initialize" do
    describe "builds an internal queue" do
      it "should build a queue with correct configuration given defaults" do
        @defaults_q = DefaultsWorker.new.queue
        @defaults_q.name.must_equal('defaults')
        @defaults_q.opts.to_hash.must_equal(
          :error_reporters => [Sneakers.error_reporters.last],
          :runner_config_file => nil,
          :metrics => nil,
          :daemonize => true,
          :start_worker_delay => 0.2,
          :workers => 4,
          :log => "sneakers.log",
          :pid_path => "sneakers.pid",
          :prefetch => 10,
          :threads => 10,
          :share_threads => false,
          :ack => true,
          :amqp => "amqp://guest:guest@localhost:5672",
          :vhost => "/",
          :exchange => "sneakers",
          :exchange_options => {
            :type => :direct,
            :durable => true,
            :auto_delete => false,
            :arguments => {}
          },
          :queue_options => {
            :durable => true,
            :auto_delete => false,
            :exclusive => false,
            :arguments => {}
          },
          :hooks => {},
          :handler => Sneakers::Handlers::Oneshot,
          :heartbeat => 30,
          :amqp_heartbeat => 30
        )
      end

      it "should build a queue with given configuration" do
        @dummy_q = DummyWorker.new.queue
        @dummy_q.name.must_equal('downloads')
        @dummy_q.opts.to_hash.must_equal(
          :error_reporters => [Sneakers.error_reporters.last],
          :runner_config_file => nil,
          :metrics => nil,
          :daemonize => true,
          :start_worker_delay => 0.2,
          :workers => 4,
          :log => "sneakers.log",
          :pid_path => "sneakers.pid",
          :prefetch => 40,
          :threads => 50,
          :share_threads => false,
          :ack => false,
          :amqp => "amqp://guest:guest@localhost:5672",
          :vhost => "/",
          :exchange => "dummy",
          :exchange_options => {
            :type => :topic,
            :durable => false,
            :auto_delete => true,
            :arguments => { 'x-arg' => 'value' }
          },
          :queue_options => {
            :durable => false,
            :auto_delete => true,
            :exclusive => true,
            :arguments => { 'x-arg' => 'value' }
          },
          :hooks => {},
          :handler => Sneakers::Handlers::Oneshot,
          :heartbeat => 5,
          :amqp_heartbeat => 30
        )
      end

      it "should build a queue with correct configuration given deprecated exchange options" do
        @deprecated_exchange_opts_q = WithDeprecatedExchangeOptionsWorker.new.queue
        @deprecated_exchange_opts_q.name.must_equal('defaults')
        @deprecated_exchange_opts_q.opts.to_hash.must_equal(
          :error_reporters => [Sneakers.error_reporters.last],
          :runner_config_file => nil,
          :metrics => nil,
          :daemonize => true,
          :start_worker_delay => 0.2,
          :workers => 4,
          :log => "sneakers.log",
          :pid_path => "sneakers.pid",
          :prefetch => 10,
          :threads => 10,
          :share_threads => false,
          :ack => true,
          :amqp => "amqp://guest:guest@localhost:5672",
          :vhost => "/",
          :exchange => "sneakers",
          :exchange_options => {
            :type => :topic,
            :durable => false,
            :auto_delete => false,
            :arguments => { 'x-arg' => 'value' }
          },
          :queue_options => {
            :durable => false,
            :auto_delete => false,
            :exclusive => false,
            :arguments => { 'x-arg2' => 'value2' }
          },
          :hooks => {},
          :handler => Sneakers::Handlers::Oneshot,
          :heartbeat => 30,
          :amqp_heartbeat => 30
        )
      end
    end

    describe "initializes worker" do
      it "should generate a worker id" do
        DummyWorker.new.id.must_match(/^worker-/)
      end
    end

    describe 'when connection provided' do
      before do
        @connection = Bunny.new(host: 'any-host.local')
        Sneakers.configure(
          exchange:          'some-exch',
          exchange_options:  { type: :direct },
          connection:        @connection,
        )
      end

      it "should build a queue with given connection" do
        @dummy_q = DummyWorker.new.queue
        @dummy_q.opts[:connection].must_equal(@connection)
      end
    end
  end


  describe "#run" do
    it "should subscribe on internal queue" do
      q = Object.new
      w = DummyWorker.new(q)
      mock(q).subscribe(w).once #XXX once?
      stub(q).name{ "test" }
      stub(q).opts { nil }
      w.run
    end
  end

  describe "#stop" do
    it "should unsubscribe from internal queue" do
      q = Object.new
      mock(q).unsubscribe.once #XXX once?
      stub(q).name { 'test-queue' }
      stub(q).opts {nil}
      w = DummyWorker.new(q)
      w.stop
    end
  end


  describe "#do_work" do
    it "should perform worker's work" do
      w = DummyWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once
      w.do_work(nil, nil, "msg", nil)
    end

    describe 'content type based deserialization' do
      before do
        Sneakers::ContentType.register(
          content_type: 'application/json',
          serializer: ->(_) {},
          deserializer: ->(payload) { JSON.parse(payload) },
        )
      end

      after do
        Sneakers::ContentType.reset!
      end

      it 'should use the registered deserializer if the content type is in the metadata' do
        w = DummyWorker.new(@queue, TestPool.new)
        mock(w).work({'foo' => 'bar'}).once
        w.do_work(nil, { content_type: 'application/json' }, '{"foo":"bar"}', nil)
      end

      it 'should use the registered deserializer if the content type is in the queue options' do
        w = JSONWorker.new(@queue, TestPool.new)
        mock(w).work({'foo' => 'bar'}).once
        w.do_work(nil, {}, '{"foo":"bar"}', nil)
      end

      it 'should use the deserializer from the queue options even if the metadata has a different content type' do
        w = JSONWorker.new(@queue, TestPool.new)
        mock(w).work({'foo' => 'bar'}).once
        w.do_work(nil, { content_type: 'not/real' }, '{"foo":"bar"}', nil)
      end
    end

    it "should catch runtime exceptions from a bad work" do
      w = AcksWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once{ raise "foo" }
      handler = Object.new
      header = Object.new
      mock(handler).error(header, nil, "msg", anything)
      mock(w.logger).error(/\[Exception error="foo" error_class=RuntimeError worker_class=AcksWorker backtrace=.*/)
      w.do_work(header, nil, "msg", handler)
    end

    it "should catch script exceptions from a bad work" do
      w = AcksWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once{ raise ScriptError }
      handler = Object.new
      header = Object.new
      mock(handler).error(header, nil, "msg", anything)
      mock(w.logger).error(/\[Exception error="ScriptError" error_class=ScriptError worker_class=AcksWorker backtrace=.*/)
      w.do_work(header, nil, "msg", handler)
    end

    it "should log exceptions from workers" do
      handler = Object.new
      header = Object.new
      w = AcksWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once{ raise "foo" }
      mock(w.logger).error(/error="foo" error_class=RuntimeError worker_class=AcksWorker backtrace=/)
      mock(handler).error(header, nil, "msg", anything)
      w.do_work(header, nil, "msg", handler)
    end

    describe "with ack" do
      before do
        @delivery_info = Object.new
        stub(@delivery_info).delivery_tag{ "tag" }

        @worker = AcksWorker.new(@queue, TestPool.new)
      end

      it "should work and handle acks" do
        handler = Object.new
        mock(handler).acknowledge(@delivery_info, nil, :ack)

        @worker.do_work(@delivery_info, nil, :ack, handler)
      end

      it "should work and handle rejects" do
        handler = Object.new
        mock(handler).reject(@delivery_info, nil, :reject)

        @worker.do_work(@delivery_info, nil, :reject, handler)
      end

      it "should work and handle requeues" do
        handler = Object.new
        mock(handler).reject(@delivery_info, nil, :requeue, true)

        @worker.do_work(@delivery_info, nil, :requeue, handler)
      end

      it "should work and handle user code errors" do
        handler = Object.new
        mock(handler).error(@delivery_info, nil, :error, anything)

        @worker.do_work(@delivery_info, nil, :error, handler)
      end
    end

    describe "without ack" do
      it "should work and not care about acking if not ack" do
        handler = Object.new
        mock(handler).reject(anything).never
        mock(handler).acknowledge(anything).never

        w = DummyWorker.new(@queue, TestPool.new)
        w.do_work(nil, nil, 'msg', handler)
      end
    end
  end


  describe 'publish' do
    it 'should be able to publish a message from working context' do
      w = PublishingWorker.new(@queue, TestPool.new)
      mock(@exchange).publish('msg', :routing_key => 'target').once
      w.do_work(nil, nil, 'msg', nil)
    end

    it 'should be able to publish arbitrary metadata' do
      w = PublishingWorker.new(@queue, TestPool.new)
      mock(@exchange).publish('msg', :routing_key => 'target', :expiration => 1).once
      w.publish 'msg', :to_queue => 'target', :expiration => 1
    end

    describe 'content_type based serialization' do
      before do
        Sneakers::ContentType.register(
          content_type: 'application/json',
          serializer: ->(payload) { JSON.dump(payload) },
          deserializer: ->(_) {},
        )
      end

      after do
        Sneakers::ContentType.reset!
      end

      it 'should be able to publish a message from working context' do
        w = JSONPublishingWorker.new(@queue, TestPool.new)
        mock(@exchange).publish('{"foo":"bar"}', :routing_key => 'target', :content_type => 'application/json').once
        w.do_work(nil, {}, {'foo' => 'bar'}, nil)
      end
    end

  end


  describe 'Logging' do
    it 'should be able to use the logging facilities' do
      log = Logger.new('/dev/null')
      mock(log).debug(anything).once
      mock(log).info("hello").once
      Sneakers::Worker.configure_logger(log)

      w = LoggingWorker.new(@queue, TestPool.new)
      w.do_work(nil,nil,'msg',nil)
    end

    it 'has a helper to constuct log prefix values' do
      w = DummyWorker.new(@queue, TestPool.new)
      w.instance_variable_set(:@id, 'worker-id')
      m = w.log_msg('foo')
      w.log_msg('foo').must_match(/\[worker-id\]\[#<Thread:.*>\]\[test-queue\]\[\{\}\] foo/)
    end

    describe '#worker_error' do
      it 'only logs backtraces if present' do
        w = DummyWorker.new(@queue, TestPool.new)
        mock(w.logger).warn('cuz')
        mock(w.logger).error(/\[Exception error="boom!" error_class=RuntimeError worker_class=DummyWorker\]/)
        w.worker_error(RuntimeError.new('boom!'), 'cuz')
      end
    end
  end


  describe 'Metrics' do
    before do
      @handler = Object.new
      @header = Object.new

      # We don't care how these are called, we're focusing on metrics here.
      stub(@handler).acknowledge
      stub(@handler).reject
      stub(@handler).error
      stub(@handler).noop

      @delivery_info = Object.new
      stub(@delivery_info).delivery_tag { "tag" }

      @w = MetricsWorker.new(@queue, TestPool.new)
      mock(@w.metrics).increment("work.MetricsWorker.started").once
      mock(@w.metrics).increment("work.MetricsWorker.ended").once
      mock(@w.metrics).timing("work.MetricsWorker.time").yields.once
    end

    it 'should be able to meter acks' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.ack").once
      @w.do_work(@delivery_info, nil, :ack, @handler)
    end

    it 'should be able to meter rejects' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.reject").once
      @w.do_work(@header, nil, :reject, @handler)
    end

    it 'should be able to meter requeue' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.requeue").once
      @w.do_work(@header, nil, :requeue, @handler)
    end

    it 'should be able to meter errors' do
      mock(@w.metrics).increment("work.MetricsWorker.handled.error").once
      mock(@w).work('msg'){ raise :error }
      @w.do_work(@delivery_info, nil, 'msg', @handler)
    end

    it 'defaults to noop when no response is specified' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.noop").once
      @w.do_work(@header, nil, nil, @handler)
    end
  end



  describe 'With Params' do
    before do
      @props = { :foo => 1 }
      @handler = Object.new
      @header = Object.new

      @delivery_info = Object.new

      stub(@handler).noop(@delivery_info, {:foo => 1}, :ack)

      @w = WithParamsWorker.new(@queue, TestPool.new)
      mock(@w.metrics).timing("work.WithParamsWorker.time").yields.once
    end

    it 'should call work_with_params and not work' do
      mock(@w).work_with_params(:ack, @delivery_info, {:foo => 1}).once
      @w.do_work(@delivery_info, {:foo => 1 }, :ack, @handler)
    end
  end
end
