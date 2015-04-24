$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'

class BenchmarkWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :durable => false,
             :ack => true,
             :threads => 50,
             :prefetch => 50,
             :timeout_job_after => 1,
             :exchange => 'dummy',
             :heartbeat => 5,
             :amqp_heartbeat => 10
  def work(msg)
    ack!
  end
end



