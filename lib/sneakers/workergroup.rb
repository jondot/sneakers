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
      pool = config[:share_threads] ? Concurrent::FixedThreadPool.new(config[:threads]) : nil

      worker_classes = config[:worker_classes]

      if worker_classes.respond_to? :call
        worker_classes = worker_classes.call
      end

      # if we don't provide a connection to a worker,
      # the queue used in the worker will create a new one
      # so if we want to have a shared bunny connection for the workers
      # we must create it here
      bunny_connection = create_connection_or_nil

      @workers = worker_classes.map{|w| w.new(nil, pool, {connection: bunny_connection}) }
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

    def create_bunny_connection
      Bunny.new(Sneakers::CONFIG[:amqp], :vhost => Sneakers::CONFIG[:vhost], :heartbeat => Sneakers::CONFIG[:heartbeat], :logger => Sneakers::logger)
    end

    def create_connection_or_nil
      config[:share_bunny_connection] ? create_bunny_connection : nil
    end
    private :create_bunny_connection, :create_connection_or_nil
  end
end
