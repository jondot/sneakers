require 'sneakers'
require 'sneakers/runner'

task :environment

namespace :sneakers do
  desc "Start work (set $WORKERS=Klass1,Klass2)"
  task :run  => :environment do
    worker_group_config_file = ENV['WORKER_GROUP_CONFIG'] || "./config/sneaker_worker_groups.json" 
    if File.exists?(worker_group_config_file)
      @pids = []
      worker_config = JSON.parse(File.read(worker_group_config_file))
      worker_config["group_names"].each do |group_name| 
        workers, missing_workers = Sneakers::Utils.parse_workers(worker_config[group_name]["classes"])
        unless missing_workers.empty?
          puts "Missing workers: #{missing_workers.join(', ')}" if missing_workers
          puts "Did you `require` properly?"
          exit(1)
        end
        @pids << fork do
          @r=Sneakers::Runner.new(workers, {:workers => worker_config[group_name]["processes"]})
          @r.run
        end
      end
      ["TERM", "USR1", "HUP", "USR2"].each do |signal|
        Signal.trap(signal){ @pids.each{|pid| Process.kill(signal, pid) } }
      end
      Process.waitall
    else
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

      r = Sneakers::Runner.new(workers)

      r.run
    end
  end
end
