require 'yaml'

module Sneakers
  class Spawner

    def self.spawn
      worker_group_config_file = ENV['WORKER_GROUP_CONFIG'] || "./config/sneaker_worker_groups.yml"
      unless File.exists?(worker_group_config_file)
        puts "No worker group file found."
        puts "Specify via ENV 'WORKER_GROUP_CONFIG' or by convention ./config/sneaker_worker_groups.yml"
        Kernel.exit(1)
      end
      @pids = []
      @exec_string = "bundle exec rake sneakers:run"
      worker_config = YAML.load(File.read(worker_group_config_file))
      worker_config.keys.each do |group_name|
        workers = worker_config[group_name]['classes']
        workers = workers.join "," if workers.is_a?(Array)
        @pids << fork do
          @exec_hash = {"WORKERS"=> workers, "WORKER_COUNT" => worker_config[group_name]["workers"].to_s}
          Kernel.exec(@exec_hash, @exec_string)
        end
      end
      ["TERM", "USR1", "HUP", "USR2"].each do |signal|
        Signal.trap(signal){ @pids.each{|pid| Process.kill(signal, pid) } }
      end
      Process.waitall
    end
  end
end
