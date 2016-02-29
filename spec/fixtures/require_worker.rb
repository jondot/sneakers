require 'sneakers'
require 'open-uri'


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

