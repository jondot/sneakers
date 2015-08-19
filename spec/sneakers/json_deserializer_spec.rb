require 'spec_helper'
require 'sneakers'

class JSONDummyWorker
  include Sneakers::Worker
  include Sneakers::Deserializer::JSON
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

class TestPool
  def process(*args,&block)
    block.call
  end
end

describe Sneakers::Deserializer::JSON do
  before do
    @queue = Object.new
    @exchange = Object.new
    stub(@queue).name { 'test-queue' }
    stub(@queue).opts { {} }
    stub(@queue).exchange { @exchange }

    Sneakers.clear!
    Sneakers.configure(:daemonize => true, :log => 'sneakers.log')
    Sneakers::Worker.configure_metrics
  end

  describe "#do_work" do
    it "should deserialise json" do
      w = JSONDummyWorker.new(@queue, TestPool.new)
      mock(w).work({"foo" => "bar"}).once
      w.do_work(nil, { content_type: 'application/json' }, '{"foo":"bar"}', nil)
    end

    it "should not deserialise json if the content type is not present" do
      w = JSONDummyWorker.new(@queue, TestPool.new)
      mock(w).work('{"foo":"bar"').once
      w.do_work(nil, {}, '{"foo":"bar"', nil)
    end
  end
end
