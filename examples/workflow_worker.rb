$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'

class WorkflowWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :env => 'test',
             :durable => false,
             :ack => true,
             :threads => 50,
             :prefetch => 50,
             :timeout_job_after => 1,
             :exchange => 'dummy',
             :heartbeat_interval => 5

  def work(msg)
    logger.info("Seriously, i'm DONE.")
    publish "cleaned up", :to_queue => "foobar"
    logger.info("Published to 'foobar'")
    ack!
  end
end


