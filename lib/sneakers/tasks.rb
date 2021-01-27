require 'sneakers'
require 'sneakers/runner'

task :environment

namespace :sneakers do
  desc "Start work (set $WORKERS=Klass1,Klass2)"
  task :run do
    Sneakers.server = true
    Rake::Task['environment'].invoke

    if defined?(::Rails)
      if defined?(::Zeitwerk)
        ::Zeitwerk::Loader.eager_load_all
      else
        ::Rails.application.eager_load!
      end
    end

    workers, missing_workers = get_worker_classes

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

You can also configure them with
  $ Sneakers.rake_worker_classes

If you use something that responds to :call it will execute that

Eventually, if nothing before applied, every class is used where you directly included the Sneakers::Worker
EOF
      exit(1)
    end
    opts = (!ENV['WORKER_COUNT'].nil? ? {:workers => ENV['WORKER_COUNT'].to_i} : {})
    r = Sneakers::Runner.new(workers, opts)

    r.run
  end

  private

  def get_worker_classes
    if ENV["WORKERS"]
      Sneakers::Utils.parse_workers(ENV['WORKERS'])
    elsif Sneakers.rake_worker_classes
      if Sneakers.rake_worker_classes.respond_to?(:call)
        [Sneakers.rake_worker_classes.call]
      else
        [Sneakers.rake_worker_classes]
      end
    else
      [Sneakers::Worker::Classes]
    end || [[]]
  end
end
