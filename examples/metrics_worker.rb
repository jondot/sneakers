$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/metrics/logging_metrics'
require 'open-uri'


class MetricsWorker
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


Sneakers.configure(:metrics => Sneakers::Metrics::LoggingMetrics.new)
r = Sneakers::Runner.new([ MetricsWorker ])
r.run




