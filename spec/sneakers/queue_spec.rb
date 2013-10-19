require 'spec_helper'
require 'sneakers'



describe Sneakers::Queue do
  before do
    Sneakers.configure(:env => 'test')
  end

  describe "#subscribe" do
    it "should setup a bunny queue according to configuration values" do
      q = Sneakers::Queue.new("downloads", 
        :prefetch => 25,
        :durable => true,
        :ack => true,
        :heartbeat => 2,
        :vhost => '/',
        :exchange => "sneakers",
        :exchange_type => :direct
      )
      mkbunny = Object.new
      mkchan = Object.new
      mkex = Object.new
      mkqueue = Object.new

      mock(mkbunny).start {}
      mock(mkbunny).create_channel{ mkchan }
      mock(Bunny).new(anything, :vhost => '/', :heartbeat => 2){ mkbunny }

      mock(mkchan).prefetch(25)
      mock(mkchan).exchange("sneakers", :type => :direct, :durable => true){ mkex }
      mock(mkchan).queue("downloads", :durable => true){ mkqueue }

      mock(mkqueue).bind(mkex, :routing_key => "downloads")
      mock(mkqueue).subscribe(:block => false, :ack => true)

      q.subscribe(Object.new)
    end
  end


end

