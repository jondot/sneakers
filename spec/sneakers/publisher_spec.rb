require 'spec_helper'
require 'sneakers'


describe Sneakers::Publisher do
  describe "#publish" do
    it "should publish a message to an exchange" do
      xchg = Object.new
      mock(xchg).publish("test msg", :routing_key => "downloads")

      p = Sneakers::Publisher.new
      p.exchange = xchg

      mock(p).ensure_connection!{}
      p.publish("test msg", :to_queue => 'downloads')
    end

    it "should not reconnect if already connected" do
      xchg = Object.new
      mock(xchg).publish("test msg", :routing_key => "downloads")

      p = Sneakers::Publisher.new
      p.exchange = xchg
      mock(p).connected?{true}
      mock(p).ensure_connection!.times(0)

      p.publish("test msg", :to_queue => 'downloads')
    end

    it "should connect to rabbitmq configured on Sneakers.configure" do
      Sneakers.configure(
        :amqp => "amqp://someuser:somepassword@somehost:5672",
        :heartbeat => 1, :exchange => 'another_exchange',
        :exchange_type => :topic,
        :durable => false)

      channel = Object.new
      mock(channel).exchange("another_exchange", :type => :topic, :durable => false) {
        mock(Object.new).publish("test msg", :routing_key => "downloads")
      }

      bunny = Object.new
      mock(bunny).start
      mock(bunny).create_channel { channel }

      mock(Bunny).new("amqp://someuser:somepassword@somehost:5672", :heartbeat => 1 ) { bunny }

      p = Sneakers::Publisher.new

      p.publish("test msg", :to_queue => 'downloads')

    end
  end
end
