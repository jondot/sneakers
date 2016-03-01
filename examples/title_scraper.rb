require "sneakers"
require 'open-uri'
require 'logger'

def compose_or_localhost(key)
  Resolv::DNS.new.getaddress(key)
rescue 
  "localhost"
end

rmq_addr = compose_or_localhost("rabbitmq")

Sneakers.configure :log => STDOUT, :amqp => "amqp://guest:guest@#{rmq_addr}:5672"
Sneakers.logger.level = Logger::INFO

class TitleScraper
  include Sneakers::Worker

  from_queue 'downloads'

  def work(msg)
    title = extract_title(open(msg))
    logger.info "FOUND <#{title}>"
    ack!
  end

  private

  def extract_title(html)
    html =~ /<title>(.*?)<\/title>/
    $1
  end
end



