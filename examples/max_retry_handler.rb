$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/maxretry'
require 'logger'

Sneakers.configure(:handler => Sneakers::Handlers::Maxretry,
                   :workers => 1,
                   :threads => 1,
                   :prefetch => 1,
                   :exchange => 'sneakers',
                   :exchange_type => 'topic',
                   :routing_key => ['#', 'something'],
                   :durable => true,
                   )
Sneakers.logger.level = Logger::DEBUG

WORKER_OPTIONS = {
  :ack => true,
  :threads => 1,
  :prefetch => 1,
  :timeout_job_after => 60,
  :heartbeat => 5,
  :amqp_heartbeat => 10,
  :retry_timeout => 5000
}

# Example of how to write a retry worker. If your rabbit system is empty, then
# you must run this twice. Once to setup the exchanges, queues and bindings a
# second time to have the sent message end up on the downloads queue.
#
# Run this via:
#   bundle exec ruby examples/max_retry_handler.rb
#
class MaxRetryWorker
  include Sneakers::Worker
  from_queue 'downloads',
      WORKER_OPTIONS.merge({
                             :arguments => {
                               :'x-dead-letter-exchange' => 'downloads-retry'
                             },
                           })

  def work(msg)
    logger.info("MaxRetryWorker rejecting msg: #{msg.inspect}")

    # We always want to reject to see if we do the proper timeout
    reject!
  end
end

# Example of a worker on the same exchange that does not fail, so it should only
# see the message once.
class SucceedingWorker
  include Sneakers::Worker
  from_queue 'uploads',
      WORKER_OPTIONS.merge({
                             :arguments => {
                               :'x-dead-letter-exchange' => 'uploads-retry'
                             },
                           })

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

r = Sneakers::Runner.new([MaxRetryWorker, SucceedingWorker])
r.run
