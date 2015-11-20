require "sneakers"
require 'open-uri'
require 'nokogiri'

require 'logger'

Sneakers.configure :log => STDOUT
Sneakers.logger.level = Logger::INFO

class TitleScraper
  include Sneakers::Worker

  from_queue 'downloads'

  def work(msg)
    doc = Nokogiri::HTML(open(msg))
    puts "#{Thread.current} working on #{msg}"
    worker_trace "FOUND <#{doc.css('title').text}>"
    ack!
  end
end



