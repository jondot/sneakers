$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/ratelimiter'
require 'sneakers/handlers/maxretry'
require 'sneakers/handlers/oneshot'
require 'logger'

# Example of how to write a rate limiter worker. If your rabbit system is empty, then
# you must run this twice. Once to setup the exchanges, queues and bindings a
# second time to have the sent message end up on the downloads queue.
#
# Run this via:
#   bundle exec ruby examples/rate_limiter_handler.rb


Sneakers.configure(:handler => Sneakers::Handlers::RateLimiter,
                   :workers => 1,
                   :threads => 1,
                   :prefetch => 1,
                   :exchange => 'sneakers'
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

class RateLimiterWorker
  include Sneakers::Worker
  from_queue 'example_with_oneshot', WORKER_OPTIONS

  def work(msg)
    logger.info("RateLimiterWorker ack message: #{msg.inspect}")
    ack!
  end
end

class RateLimiterMaxRetryWorker
  include Sneakers::Worker
  from_queue 'example_with_maxretry', WORKER_OPTIONS.merge({
                                                      :rate_limiter_decorated_handler_func => ->(*args) {Sneakers::Handlers::Maxretry.new(*args)},
                                                      :arguments => {
                                                          :'x-dead-letter-exchange' => 'example_with_maxretry-retry'
                                                      }
                                                  })

  def work(msg)
    if rand(4) == 0 #fail 25% of messages
      logger.info("RateLimiterMaxRetryWorker reject msg: #{msg.inspect}")
      reject!
    else
      logger.info("RateLimiterMaxRetryWorker ack message: #{msg.inspect}")
      ack!
    end
  end
end

messages = 10
puts "feeding messages in"
messages.times {
  Sneakers.publish(" -- example_with_oneshot message -- ",
                   :to_queue => 'example_with_oneshot',
                   :persistence => true)
  Sneakers.publish(" -- example_with_maxretry message -- ",
                   :to_queue => 'example_with_maxretry',
                   :persistence => true)
}
puts "done"

r = Sneakers::Runner.new([RateLimiterMaxRetryWorker, RateLimiterWorker])
r.run