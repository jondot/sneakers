require 'sneakers/runner'

module Sneakers
  module Cluster
    class << self
      attr_reader :after_fork_hook, :current_workgroup

      def configure_workrgoups(hash)
        @config = hash
      end

      def after_fork(&block)
        @after_fork_hook = block
      end

      def apply_workgroup_config!
        return unless @config
        Sneakers.configure(@config.fetch(current_workgroup) { {} })
      end

      def start(workgroups = nil)
        workgroups ||= Sneakers::Worker::Classes.map(&:workgroup).uniq
        workgroups = Array(workgroups)
        if workgroups.count == 1
          run_workgroup(workgroups.first)
        else
          fork_servers(workgroups)
        end
      end

      private

      def fork_servers(workgroups)
        hook = Sneakers::CONFIG[:hooks][:before_fork]
        hook.call if hook
        pids = workgroups.map do |workgroup|
          fork do
            $0 = "sneakers-#{workgroup}" # set name for supervisor process and childs
            run_workgroup(workgroup)
          end
        end
        forward_signals(pids)
        Process.waitall
      end

      def forward_signals(pids)
        %w[TERM USR1 HUP USR2 INT].each do |signal|
          Signal.trap(signal) do
            pids.each do |pid|
              begin
                Process.kill(signal, pid)
              rescue Errno::ESRCH, RangeError # don't crash if child is dead
              end
            end
          end
        end
      end

      def run_workgroup(workgroup)
        @current_workgroup = workgroup
        apply_workgroup_config!
        after_fork_hook.call if after_fork_hook
        worker_classes = Sneakers::Worker::Classes.select { |klass| klass.workgroup == workgroup }
        Sneakers.logger.info "Running workgroup #{workgroup} with config #{Sneakers::CONFIG.inspect}"
        run_sneakers(worker_classes)
      end

      def run_sneakers(worker_classes)
        Sneakers::Runner.new(worker_classes, workers: Sneakers::CONFIG[:workers]).run
      end
    end
  end
end
