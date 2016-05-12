require 'sneakers'
require 'sneakers/runner'

task :environment

namespace :sneakers do
  desc "Start work (set $WORKERS=Klass1,Klass2)"
  task :run do
    Sneakers.server = true
    Rake::Task['environment'].invoke

    if defined?(::Rails)
      ::Rails.application.eager_load!
    end

    if ENV["WORKERS"].nil?
      workers = Sneakers::Worker::Classes
    else
      workers, missing_workers = Sneakers::Utils.parse_workers(ENV['WORKERS'])
    end

    unless missing_workers.nil? || missing_workers.empty?
      puts "Missing workers: #{missing_workers.join(', ')}" if missing_workers
      puts "Did you `require` properly?"
      exit(1)
    end

    if workers.empty?
      puts <<EOF
Error: No workers found.
Please set the classes of the workers you want to run like so:

  $ export WORKERS=MyWorker,FooWorker
  $ rake sneakers:run

EOF
      exit(1)
    end
    opts = (!ENV['WORKER_COUNT'].nil? ? {:workers => ENV['WORKER_COUNT'].to_i} : {})
    r = Sneakers::Runner.new(workers, opts)

    r.run
  end

  desc "Retries all failed message for WORKER (Only if using Maxretry Handler)"
  task :retry_failed_messages do

    if ENV["WORKER"].nil?
      puts <<EOF
Error: No worker defined.
Please set the worker class you want to retry like so:

  $ export WORKER=MyWorker
  $ rake sneakers:enqueue_failed_messages

or:

  $ rake sneakers:enqueue_failed_messages WORKER=MyWorker

EOF
    exit(1)
    end

    worker_class = ENV['WORKER'].constantize
    config = Sneakers::CONFIG.merge worker_class.queue_opts
    bunny = Bunny.new(config[:amqp], :vhost => config[:vhost], :heartbeat => config[:heartbeat], :logger => Sneakers::logger)
    bunny.start
    channel = bunny.create_channel
    channel.prefetch config[:prefetch]
    exchange = channel.exchange(config[:exchange], config[:exchange_options])
    queue = channel.queue(worker_class.queue_name + "-error", :durable => true)

    delivery_info, properties, payload = queue.pop

    while payload
      error_data = JSON.parse(payload)
      msg = Base64.decode64(error_data["payload"])
      
      exchange.publish msg, :routing_key => delivery_info[:routing_key], :headers => error_data["headers"]
      
      delivery_info, properties, payload = queue.pop
    end


  end

end
