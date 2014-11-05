require 'spec_helper'
require 'sneakers'
require 'timeout'


class DummyWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :durable => false,
             :ack => false,
             :threads => 50,
             :prefetch => 40,
             :timeout_job_after => 1,
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

class TimeoutWorker
  include Sneakers::Worker
  from_queue 'defaults',
    :timeout_job_after => 0.5,
    :ack => true

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



class LoggingWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => false

  def work(msg)
    logger.info "hello"
  end
end


class MetricsWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true,
             :timeout_job_after => 0.5

  def work(msg)
    metrics.increment "foobar"
    msg
  end
end

class WithParamsWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true,
             :timeout_job_after => 0.5

  def work_with_params(msg, delivery_info, metadata)
    msg
  end
end


class TestPool
  def process(*args,&block)
    block.call
  end
end

def with_test_queuefactory(ctx, ack=true, msg=nil, nowork=false)
  qf = Object.new
  q = Object.new
  s = Object.new
  hdr = Object.new
  mock(qf).build_queue(anything, anything, anything) { q }
  mock(q).subscribe(anything){ s }

  mock(s).each(anything) { |h,b| b.call(hdr, msg) unless nowork }
  mock(hdr).ack{true} if !nowork && ack
  mock(hdr).reject{true} if !nowork && !ack

  mock(ctx).queue_factory { qf } # should return our own
end

describe Sneakers::Worker do
  before do
    @queue = Object.new
    @exchange = Object.new
    stub(@queue).name { 'test-queue' }
    stub(@queue).opts { {} }
    stub(@queue).exchange { @exchange }

    Sneakers.configure(:daemonize => true, :log => 'sneakers.log')
    Sneakers::Worker.configure_metrics
  end

  describe ".enqueue" do
    it "publishes a message to the class queue" do
      message = "my message"
      mock = MiniTest::Mock.new

      mock.expect(:publish, true) do |msg, opts|
        msg.must_equal(message)
        opts.must_equal(:to_queue => "defaults")
      end

      stub(Sneakers::Publisher).new { mock }
      DefaultsWorker.enqueue(message)
    end
  end

  describe "#initialize" do
    describe "builds an internal queue" do
      before do
        @dummy_q = DummyWorker.new.queue
        @defaults_q = DefaultsWorker.new.queue
      end

      it "should build a queue with correct configuration given defaults" do
        @defaults_q.name.must_equal('defaults')
        @defaults_q.opts.to_hash.must_equal(
          {:runner_config_file=>nil, :metrics=>nil, :daemonize=>true, :start_worker_delay=>0.2, :workers=>4, :log=>"sneakers.log", :pid_path=>"sneakers.pid", :timeout_job_after=>5, :prefetch=>10, :threads=>10, :durable=>true, :ack=>true, :amqp=>"amqp://guest:guest@localhost:5672", :vhost=>"/", :exchange=>"sneakers", :exchange_type=>:direct, :hooks=>{}, :handler=>Sneakers::Handlers::Oneshot, :heartbeat => 2}
        )
      end

      it "should build a queue with given configuration" do
        @dummy_q.name.must_equal('downloads')
        @dummy_q.opts.to_hash.must_equal(
          {:runner_config_file=>nil, :metrics=>nil, :daemonize=>true, :start_worker_delay=>0.2, :workers=>4, :log=>"sneakers.log", :pid_path=>"sneakers.pid", :timeout_job_after=>1, :prefetch=>40, :threads=>50, :durable=>false, :ack=>false, :amqp=>"amqp://guest:guest@localhost:5672", :vhost=>"/", :exchange=>"dummy", :exchange_type=>:direct, :hooks=>{}, :handler=>Sneakers::Handlers::Oneshot, :heartbeat =>5}
        )
      end
    end

    describe "initializes worker" do
      it "should generate a worker id" do
        DummyWorker.new.id.must_match(/^worker-/)
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

    it "should catch runtime exceptions from a bad work" do
      w = AcksWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once{ raise "foo" }
      handler = Object.new
      header = Object.new
      mock(handler).error(header, nil, "msg", anything)
      mock(w.logger).error(/unexpected error \[Exception error="foo" error_class=RuntimeError backtrace=.*/)
      w.do_work(header, nil, "msg", handler)
    end

    it "should log exceptions from workers" do
      handler = Object.new
      header = Object.new
      w = AcksWorker.new(@queue, TestPool.new)
      mock(w).work("msg").once{ raise "foo" }
      mock(w.logger).error(/error="foo" error_class=RuntimeError backtrace=/)
      mock(handler).error(header, nil, "msg", anything)
      w.do_work(header, nil, "msg", handler)
    end

    it "should timeout if a work takes too long" do
      w = TimeoutWorker.new(@queue, TestPool.new)
      stub(w).work("msg"){ sleep 10 }

      handler = Object.new
      header = Object.new

      mock(handler).timeout(header, nil, "msg")
      mock(w.logger).error(/timeout/)

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

      it "should work and handle user-land timeouts" do
        handler = Object.new
        mock(handler).timeout(@delivery_info, nil, :timeout)

        @worker.do_work(@delivery_info, nil, :timeout, handler)
      end

      it "should work and handle user-land error" do
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
        mock(w.logger).error(/cuz \[Exception error="boom!" error_class=RuntimeError\]/)
        w.worker_error('cuz', RuntimeError.new('boom!'))
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
      stub(@handler).timeout
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

    it 'should be able to meter timeouts' do
      mock(@w.metrics).increment("work.MetricsWorker.handled.timeout").once
      mock(@w).work('msg'){ sleep 10 }
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
