def cleanup_rabbitmq(client)
  # clean up all integration queues; admin interface must be installed
  # in integration env
  integration_log 'cleaning up RabbitMQ'

  cleanup_queues(client)
  cleanup_exchanges(client)
end

def cleanup_exchanges(client)
  exchanges = client.list_exchanges
  exchanges.each do |exchange|
    name = exchange.name
    if name.start_with? 'integration_'
      client.delete_exchange('/', name)
      integration_log "delete exchange #{name}."
    end
  end
end

def cleanup_queues(client)
  queues = client.list_queues
  queues.each do |q|
    name = q.name
    if name.start_with? 'integration_'
      client.delete_queue('/', name)
      integration_log "delete queue #{name}."
    end
  end
end

def x_death_array(message_headers, queue_name)
  message_headers['x-death'].select do |x|
    x['queue'] == queue_name
  end
end

def cleanup_redis(client)
  keys = client.keys('integration_*')
  integration_log 'cleaning up redis'
  client.del(keys) unless keys.empty?
end

def prepare_sneakers(opts = {})
  Sneakers.clear!
  Sneakers.configure(opts)
  Sneakers.logger.level = Logger::ERROR
end

def get_message_from_queue(queue_name)
  connection = Bunny.new
  connection.start
  channel = connection.create_channel
  message = channel.basic_get(queue_name)
  channel.acknowledge(message.first.delivery_tag) if message.first

  message
end

def start_worker(worker)
  integration_log 'starting workers.'
  runner = Sneakers::Runner.new([worker])
  pid = fork do
    runner.run
  end

  integration_log 'waiting for workers to stabilize (5s).'
  sleep 5

  pid
end

def integration_log(msg)
  puts msg if ENV['INTEGRATION_LOG']
end
