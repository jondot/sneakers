require 'sneakers'
require 'thread'
require 'redis'


redis_addr = compose_or_localhost("redis")
puts "REDIS is at #{redis_addr}"
$redis = Redis.new(:host => redis_addr)

class IntegrationWorker
  include Sneakers::Worker
  
  def work(msg)
    $redis.incr(self.class.queue_name)
    ack!
  end
end

