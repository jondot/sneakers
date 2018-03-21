$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/metrics/newrelic_metrics'
require 'open-uri'
require 'newrelic_rpm'

# With this configuration will send two types of data to newrelic server:
# 1. Transaction data which you would see under  'Applications'
# 2. Metrics where you will be able to see by configuring a dashboardi, available for enterprise accounts
#
# You should have newrelic.yml in the 'config' folder with the proper account settings

Sneakers::Metrics::NewrelicMetrics.eagent ::NewRelic
Sneakers.configure metrics: Sneakers::Metrics::NewrelicMetrics.new

class MetricsWorker
  include Sneakers::Worker
  include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation

  from_queue 'downloads'

  def work(msg)
    title = extract_title(open(msg))
    logger.info "FOUND <#{title}>"
    ack!
  end

  add_transaction_tracer :work, name: 'MetricsWorker', params: 'args[0]', category: :task

  private

  def extract_title(html)
    html =~ /<title>(.*?)<\/title>/
    $1
  end
end

r = Sneakers::Runner.new([ MetricsWorker ])
r.run
