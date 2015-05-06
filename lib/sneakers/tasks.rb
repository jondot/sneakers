require 'sneakers'
require 'sneakers/runner'

task :environment

namespace :sneakers do
  desc "Start work (set $WORKERS=Klass1,Klass2)"
  task :run  => :environment do

    workers, missing_workers = Sneakers::Utils.parse_workers(ENV['WORKERS'])

    unless missing_workers.empty?
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
    opts = {}
    opts[:workers] = ENV['WORKER_COUNT'].to_i if ENV['WORKER_COUNT'].present?
    opts[:pid_path] = ENV['PID_PATH'].to_s if ENV['PID_PATH'].present?
    r = Sneakers::Runner.new(workers, opts)

    r.run
  end
end
