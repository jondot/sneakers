require 'spec_helper'
require 'sneakers'
require 'timeout'


class DummyWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :env => 'test',
             :durable => false,
             :ack => false,
             :threads => 50,
             :prefetch => 40,
             :timeout_job_after => 1,
             :exchange => 'dummy',
             :heartbeat_interval => 5

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



class TestPool
  def process(*args,&block)
    block.call
  end
end

class TestHandler
  def acknowledge(tag);  end
  def reject(tag);  end
  def error(tag, err); end
  def timeout(tag); end
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
    stub(@queue).name { 'test-queue' }
    stub(@queue).opts { {} }

    Sneakers.configure(:env => 'test')
    Sneakers::Worker.configure_logger(Logger.new('/dev/null'))
    Sneakers::Worker.configure_metrics
  end

  describe "#initialize" do
    describe "builds an internal queue" do
      before do
        @dummy_q = DummyWorker.new.queue
        @defaults_q = DefaultsWorker.new.queue
      end

      it "should build a queue with correct configuration given defaults" do
        @defaults_q.name.must_equal('defaults_test')
        @defaults_q.opts.must_equal(
           :durable => true,
           :ack => true,
           :prefetch => 10,
           :heartbeat_interval => 2,
           :exchange => 'sneakers'
        )
      end

      it "should build a queue with given configuration" do
        @dummy_q.name.must_equal('downloads_test')
        @dummy_q.opts.must_equal(
           :durable => false,
           :ack => false,
           :prefetch => 40,
           :heartbeat_interval => 5,
           :exchange => 'dummy'
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
      mock(handler).error("tag", anything)
      header = Object.new
      stub(header).delivery_tag { "tag" }
      w.do_work(header, nil, "msg", handler)
    end

    it "should timeout if a work takes too long" do
      w = TimeoutWorker.new(@queue, TestPool.new)
      stub(w).work("msg"){ sleep 10 }

      handler = Object.new
      mock(handler).timeout("tag")

      header = Object.new
      stub(header).delivery_tag { "tag" }

      w.do_work(header, nil, "msg", handler)
    end

    describe "with ack" do
      before do
        @header = Object.new
        stub(@header).delivery_tag{ "tag" }

        @worker = AcksWorker.new(@queue, TestPool.new)
      end

      it "should work and handle acks" do
        handler = Object.new
        mock(handler).acknowledge("tag")

        @worker.do_work(@header, nil, :ack, handler)
      end

      it "should work and handle nacks" do
        handler = Object.new
        mock(handler).reject("tag")

        @worker.do_work(@header, nil, :nack, handler)
      end

      it "should work and handle rejects" do
        handler = Object.new
        mock(handler).reject("tag")

        @worker.do_work(@header, nil, :reject, handler)
      end

      it "should work and handle user-land timeouts" do
        handler = Object.new
        mock(handler).timeout("tag")

        @worker.do_work(@header, nil, :timeout, handler)
      end

      it "should work and handle user-land error" do
        handler = Object.new
        mock(handler).error("tag",anything)

        @worker.do_work(@header, nil, :error, handler)
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
      mock(w).publish('msg', :to_queue => 'target').once
      w.do_work(nil, nil, 'msg', nil)

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
  end


  describe 'Metrics' do
    before do
      @handler = Object.new
      stub(@handler).acknowledge("tag")
      stub(@handler).reject("tag")
      stub(@handler).timeout("tag")
      stub(@handler).error("tag", anything)

      @header = Object.new
      stub(@header).delivery_tag { "tag" }

      @w = MetricsWorker.new(@queue, TestPool.new)
      mock(@w.metrics).increment("work.MetricsWorker.started").once
      mock(@w.metrics).increment("work.MetricsWorker.ended").once
      mock(@w.metrics).timing("work.MetricsWorker.time").yields.once
    end

    it 'should be able to meter acks' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.ack").once
      @w.do_work(@header, nil, :ack, @handler)
    end

    it 'should be able to meter rejects' do
      mock(@w.metrics).increment("foobar").once
      mock(@w.metrics).increment("work.MetricsWorker.handled.reject").once
      @w.do_work(@header, nil, nil, @handler)
    end

    it 'should be able to meter errors' do
      mock(@w.metrics).increment("work.MetricsWorker.handled.error").once
      mock(@w).work('msg'){ raise :error }
      @w.do_work(@header, nil, 'msg', @handler)
    end

    it 'should be able to meter timeouts' do
      mock(@w.metrics).increment("work.MetricsWorker.handled.timeout").once
      mock(@w).work('msg'){ sleep 10 }
      @w.do_work(@header, nil, 'msg', @handler)
    end
  end

end
