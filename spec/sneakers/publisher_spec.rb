require 'spec_helper'
require 'sneakers'


describe Sneakers::Publisher do
  before do
    Sneakers.configure(:env => 'test')
  end

  describe "#publish" do
    it "should publish a message to an exchange" do
      xchg = Object.new
      mock(xchg).publish("test msg", :routing_key => "downloads_test")

      p = Sneakers::Publisher.new
      p.exchange = xchg

      mock(p).ensure_connection!{}
      p.publish("test msg", :to_queue => 'downloads')
    end

    it "should not reconnect if already connected" do
      xchg = Object.new
      mock(xchg).publish("test msg", :routing_key => "downloads_test")

      p = Sneakers::Publisher.new
      p.exchange = xchg
      mock(p).connected?{true}
      mock(p).ensure_connection!.times(0)

      p.publish("test msg", :to_queue => 'downloads')
    end
  end


end

