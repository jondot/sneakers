require 'spec_helper'
require 'sneakers'

describe Sneakers::Queue do
  let :queue_vars do
    {
      :prefetch => 25,
      :ack => true,
      :heartbeat => 2,
      :vhost => '/',
      :exchange => "sneakers",
      :exchange_options => {
        :type => :direct,
        durable: true,
        :arguments => { 'x-arg' => 'value' }
      },
      queue_options: {
        durable: true
      }
    }
  end

  before do
    Sneakers.configure

    @mkworker = Object.new
    stub(@mkworker).opts { { :exchange => 'test-exchange' } }
    @mkchan = Object.new
    mock(@mkchan).prefetch(25)
    @mkex = Object.new
    @mkqueue = Object.new
  end

  describe 'with our own Bunny object' do
    before do
      @mkbunny = Object.new
      @mkqueue_nondurable = Object.new

      mock(@mkbunny).start {}
      mock(@mkbunny).create_channel{ @mkchan }
      mock(Bunny).new(
        anything,
        hash_including(:vhost => '/', :heartbeat => 2)
      ){ @mkbunny }
    end

    describe "#subscribe with sneakers exchange" do
      before do
        mock(@mkchan).exchange("sneakers",
                               :type => :direct,
                               :durable => true,
                               :arguments => { 'x-arg' => 'value' }){ @mkex }
      end

      it "should setup a bunny queue according to configuration values" do
        mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
        q = Sneakers::Queue.new("downloads", queue_vars)

        mock(@mkqueue).bind(@mkex, :routing_key => "downloads")
        mock(@mkqueue).subscribe(:block => false, :manual_ack => true)

        q.subscribe(@mkworker)
      end

      it "supports multiple routing_keys" do
        mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
        q = Sneakers::Queue.new("downloads",
                                queue_vars.merge(:routing_key => ["alpha", "beta"]))

        mock(@mkqueue).bind(@mkex, :routing_key => "alpha")
        mock(@mkqueue).bind(@mkex, :routing_key => "beta")
        mock(@mkqueue).subscribe(:block => false, :manual_ack => true)

        q.subscribe(@mkworker)
      end

      it "supports setting arguments when binding" do
        mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
        q = Sneakers::Queue.new("downloads",
                                queue_vars.merge(:bind_arguments => { "os" => "linux", "cores" => 8 }))

        mock(@mkqueue).bind(@mkex, :routing_key => "downloads", :arguments => { "os" => "linux", "cores" => 8 })
        mock(@mkqueue).subscribe(:block => false, :manual_ack => true)

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
        queue_vars[:queue_options][:durable] = false
        q = Sneakers::Queue.new("test_nondurable", queue_vars)

        mock(@mkqueue_nondurable).bind(@mkex, :routing_key => "test_nondurable")
        mock(@mkqueue_nondurable).subscribe(:block => false, :manual_ack => true)

        q.subscribe(@mkworker)
        myqueue = q.instance_variable_get(:@queue)
      end
    end

    describe "#subscribe with default exchange" do
      before do
        # expect default exchange
        queue_vars[:exchange] = ""
        mock(@mkchan).exchange("",
                               :type => :direct,
                               :durable => true,
                               :arguments => {"x-arg" => "value"}){ @mkex }
      end

      it "does not bind to exchange" do
        mock(@mkchan).queue("downloads", :durable => true) { @mkqueue }
        @handler = Object.new
        worker_opts = { :handler => @handler }
        stub(@mkworker).opts { worker_opts }
        mock(@handler).new(@mkchan, @mkqueue, worker_opts).once

        stub(@mkqueue).bind do
          raise "bind should not be called"
        end

        stub(@mkqueue).subscribe
        q = Sneakers::Queue.new("downloads", queue_vars)
        q.subscribe(@mkworker)
      end
    end
  end

  describe 'with an externally-provided connection' do
    describe '#subscribe' do
      before do
        @external_connection = Bunny.new
        mock(@external_connection).start {}
        mock(@external_connection).create_channel{ @mkchan }
        mock(@mkchan).exchange("sneakers",
                               :type => :direct,
                               :durable => true,
                               :arguments => { 'x-arg' => 'value' }){ @mkex }

        queue_name = 'foo'
        mock(@mkchan).queue(queue_name, :durable => true) { @mkqueue }
        mock(@mkqueue).bind(@mkex, :routing_key => queue_name)
        mock(@mkqueue).subscribe(:block => false, :manual_ack => true)

        my_vars = queue_vars.merge(:connection => @external_connection)
        @q = Sneakers::Queue.new(queue_name, my_vars)
      end

      it 'uses that object' do
        @q.subscribe(@mkworker)
        @q.instance_variable_get(:@bunny).must_equal @external_connection
      end
    end
  end
end
