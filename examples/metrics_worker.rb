$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/metrics/logging_metrics'
require 'open-uri'
require 'nokogiri'


class MetricsWorker
  include Sneakers::Worker

  from_queue 'downloads'

  def work(msg)
    doc = Nokogiri::HTML(open(msg))
    logger.info "FOUND <#{doc.css('title').text}>"
    ack!
  end
end


Sneakers.configure(:metrics => Sneakers::Metrics::LoggingMetrics.new)
r = Sneakers::Runner.new([ MetricsWorker ])
r.run




