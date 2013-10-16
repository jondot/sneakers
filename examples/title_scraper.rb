$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'open-uri'
require 'nokogiri'


class TitleScraper
  include Sneakers::Worker

  from_queue 'downloads'

  def work(msg)
    doc = Nokogiri::HTML(open(msg))
    worker_trace "FOUND <#{doc.css('title').text}>"
    ack!
  end
end



