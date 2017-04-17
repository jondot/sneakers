$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/expbackoff'
require 'logger'

Sneakers.configure(:handler => Sneakers::Handlers::Expbackoff,
                   :workers => 1,
                   :threads => 1,
                   :prefetch => 1,
                   :exchange => 'sneakers-exp',
                   :exchange_options => { :type => 'topic', durable: true },
                   :routing_key => ['#', 'something'],
                   :retry_max_times => 3,
                   :retry_backoff_multiplier => 100
                   )
Sneakers.logger.level = Logger::DEBUG

WORKER_OPTIONS = {
  :ack => true,
  :threads => 1,
  :prefetch => 1,
  :timeout_job_after => 60,
  :heartbeat => 5,
  :amqp_heartbeat => 10
}

# Example of how to write a retry worker. If your rabbit system is empty, then
# you must run this twice. Once to setup the exchanges, queues and bindings a
# second time to have the sent message end up on the downloads queue.
#
# Run this via:
#   bundle exec ruby examples/exp_backoff_handler.rb
#
class ExpBackoffWorker
  include Sneakers::Worker
  from_queue 'downloads-exp', WORKER_OPTIONS

  def work(msg)
    logger.info("ExpBackoffWorker rejecting msg: #{msg.inspect}")

    # We always want to reject to see if we do the proper timeout
    reject!
  end
end

# Example of a worker on the same exchange that does not fail, so it should only
# see the message once.
class SucceedingWorker
  include Sneakers::Worker
  from_queue 'uploads-exp', WORKER_OPTIONS

  def work(msg)
    logger.info("SucceedingWorker succeeding on msg: #{msg.inspect}")
    ack!
  end
end

messages = 1
puts "feeding messages in"
messages.times {
  Sneakers.publish(" -- message -- ",
                   :to_queue => 'anywhere',
                   :persistence => true)
}
puts "done"

r = Sneakers::Runner.new([ExpBackoffWorker, SucceedingWorker])
r.run
