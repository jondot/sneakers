require 'sneakers'
require 'thread'
require 'redis'

require 'sneakers/handlers/maxretry'

# This worker ... works
class MaxretryWorker
  include Sneakers::Worker

  def work(_)
    ack!
  end
end

# This worker fails
class FailingMaxretryWorker
  include Sneakers::Worker

  def work(_)
    reject!
  end
end

# This worker fails once
class RetryOnceWorker
  include Sneakers::Worker

  def work_with_params(_, delivery_info, message_properties)
    if message_properties[:headers].nil? ||
       message_properties[:headers]['x-death'].nil?
      reject!
    else
      dump = JSON.dump(
        'delivery_info' => delivery_info.to_hash,
        'message_properties' => message_properties.to_hash
      )
      Redis.new.set(
        self.class.queue_name,
        dump
      )
      ack!
    end
  end
end
