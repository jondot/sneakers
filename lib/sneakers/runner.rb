module Sneakers
  class Runner
    def initialize(worker_classes, opts={})
      @worker_classes = worker_classes
      @is_running = false
    end

    def run
      # pool = config[:share_threads] ? Thread.pool(config[:threads]) : nil
      @workers = @worker_classes.map{|w| w.new(nil,nil)}
      @workers.each{|w| w.run }
      @is_running = true
      while @is_running do
        sleep 1
        Sneakers.logger.info("Heartbeat: running threads [#{Thread.list.count}]")
      end

    end

    def stop
      Sneakers.logger.info("Shutting down workers")
      @workers.each do |worker|
        worker.stop
      end
      @is_running = false
    end
  end
end

