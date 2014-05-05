$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'sneakers/handlers/maxretry'
require 'logger'

Sneakers.configure(:handler => Sneakers::Handlers::Maxretry, :workers => 1, :threads => 1, :prefetch => 1)
Sneakers.logger.level = Logger::INFO

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
             :ack => true,
             :threads => 1,
             :prefetch => 1,
             :timeout_job_after => 60,
             :exchange => 'sneakers',
             :heartbeat => 5,
             :arguments => {
              :'x-dead-letter-exchange' => 'sneakers-retry'
             }

  def work(msg)

    puts "Got message #{msg} and rejecting now"

    # We always want to reject to see if we do the proper timeout
    reject!

  end
end

messages = 1
puts "feeding messages in"
messages.times {
  MaxRetryWorker.enqueue("{}")
}
puts "done"

r = Sneakers::Runner.new([ MaxRetryWorker ])
r.run
