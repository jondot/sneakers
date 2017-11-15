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
    if defined?(::Rails) && defined?(::ActiveJob::Base)
      workers -= [ActiveJob::QueueAdapters::SneakersAdapter::JobWrapper]
      jobs = ::ActiveJob::Base.descendants
      not_abstract_jobs = jobs.select { |j| j.instance_methods.include?(:perform) }
      workers += not_abstract_jobs.map do |job|
        q = job.queue_name # From ActiveJob::QueueName.queue_name
        q_name = q.is_a?(Proc) ? q[].to_s : q.to_s
        worker_klass = "ActiveJobWorker" + Digest::MD5.hexdigest(q_name) # From rails/activejob/test/support/integration/adapters/sneakers.rb
        Sneakers.const_set(worker_klass, Class.new(ActiveJob::QueueAdapters::SneakersAdapter::JobWrapper) do
          from_queue q_name
        end)
        "Sneakers::#{worker_klass}".constantize
      end
    end
    r = Sneakers::Runner.new(workers, opts)

    r.run
  end
end
