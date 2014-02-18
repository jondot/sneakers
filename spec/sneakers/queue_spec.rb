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

      mock(@mkbunny).start {}
      mock(@mkbunny).create_channel{ @mkchan }
      mock(Bunny).new(anything, :vhost => '/', :heartbeat => 2){ @mkbunny }

      mock(@mkchan).prefetch(25)
      mock(@mkchan).exchange("sneakers", :type => :direct, :durable => true){ @mkex }
      mock(@mkchan).queue("downloads", :durable => true){ @mkqueue }
    end

    it "should setup a bunny queue according to configuration values" do
      q = Sneakers::Queue.new("downloads", queue_vars)

      mock(@mkqueue).bind(@mkex, :routing_key => "downloads")
      mock(@mkqueue).subscribe(:block => false, :ack => true)

      q.subscribe(Object.new)
    end

    it "supports multiple routing_keys" do
      q = Sneakers::Queue.new("downloads",
                              queue_vars.merge(:routing_key => ["alpha", "beta"]))

      mock(@mkqueue).bind(@mkex, :routing_key => "alpha")
      mock(@mkqueue).bind(@mkex, :routing_key => "beta")
      mock(@mkqueue).subscribe(:block => false, :ack => true)

      q.subscribe(Object.new)
    end
  end


end

