module Sneakers
  module WorkerGroup
    @workers = []

    def initialize
      @stop_flag = ServerEngine::BlockingFlag.new
    end

    def before_fork
      fbefore = Sneakers::CONFIG[:hooks][:before_fork]
      fbefore.call if fbefore
    end

    def after_fork # note! this is not Serverengine#after_start, this is ours!
      fafter = Sneakers::CONFIG[:hooks][:after_fork]
      fafter.call if fafter
    end

    def run
      after_fork

      # Allocate single thread pool if share_threads is set. This improves load balancing
      # when used with many workers.
      pool = config[:share_threads] ? Thread.pool(config[:threads]) : nil

      @workers = config[:worker_classes].map{|w| w.new(nil, pool) }
      # if more than one worker this should be per worker
      # accumulate clients and consumers as well
      @workers.each do |worker|
        worker.run
      end
      # end per worker
      #
      until @stop_flag.wait_for_set(Sneakers::CONFIG[:amqp_heartbeat])
        Sneakers.logger.debug("Heartbeat: running threads [#{Thread.list.count}]")
        # report aggregated stats?
      end

    end

    def stop
      Sneakers.logger.info("Shutting down workers")
      @workers.each do |worker|
        worker.stop
      end
      @stop_flag.set!
    end

  end
end
