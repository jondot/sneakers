require 'spec_helper'
require 'sneakers'



describe Sneakers::Queue do
  before do
    Sneakers.configure
  end

  describe "#subscribe" do
    let :queue_vars do
      {
        :prefetch => 25,
        :durable => true,
        :ack => true,
        :heartbeat => 2,
        :vhost => '/',
        :exchange => "sneakers",
        :exchange_type => :direct
      }
    end

    before do
      @mkbunny = Object.new
      @mkchan = Object.new
      @mkex = Object.new
      @mkqueue = Object.new
      @mkqueue_nondurable = Object.new
      @mkworker = Object.new

      mock(@mkbunny).start {}
      mock(@mkbunny).create_channel{ @mkchan }
      mock(Bunny).new(anything, :vhost => '/', :heartbeat => 2){ @mkbunny }

      mock(@mkchan).prefetch(25)
      mock(@mkchan).exchange("sneakers", :type => :direct, :durable => true){ @mkex }

      stub(@mkworker).opts { { :exchange => 'test-exchange' } }
    end

    it "should setup a bunny queue according to configuration values" do
      mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
      q = Sneakers::Queue.new("downloads", queue_vars)

      mock(@mkqueue).bind(@mkex, :routing_key => "downloads")
      mock(@mkqueue).subscribe(:block => false, :ack => true)

      q.subscribe(@mkworker)
    end

    it "supports multiple routing_keys" do
      mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
      q = Sneakers::Queue.new("downloads",
                              queue_vars.merge(:routing_key => ["alpha", "beta"]))

      mock(@mkqueue).bind(@mkex, :routing_key => "alpha")
      mock(@mkqueue).bind(@mkex, :routing_key => "beta")
      mock(@mkqueue).subscribe(:block => false, :ack => true)

      q.subscribe(@mkworker)
    end

    it "will use whatever handler the worker specifies" do
      mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
      @handler = Object.new
      worker_opts = { :handler => @handler }
      stub(@mkworker).opts { worker_opts }
      mock(@handler).new(@mkchan, @mkqueue, worker_opts).once

      stub(@mkqueue).bind
      stub(@mkqueue).subscribe
      q = Sneakers::Queue.new("downloads", queue_vars)
      q.subscribe(@mkworker)
    end

    it "creates a non-durable queue if :queue_durable => false" do
      mock(@mkchan).queue("test_nondurable", :durable => false) { @mkqueue_nondurable }
      queue_vars[:queue_durable] = false
      q = Sneakers::Queue.new("test_nondurable", queue_vars)

      mock(@mkqueue_nondurable).bind(@mkex, :routing_key => "test_nondurable")
      mock(@mkqueue_nondurable).subscribe(:block => false, :ack => true)

      q.subscribe(@mkworker)
      myqueue = q.instance_variable_get(:@queue)
    end
  end
end

