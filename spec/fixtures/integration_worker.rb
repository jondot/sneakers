require 'sneakers'
require 'thread'
require 'redis'

$redis = Redis.new

class IntegrationWorker
  include Sneakers::Worker
  
  def work(msg)
    $redis.incr(self.class.queue_name)
    ack!
  end
end

