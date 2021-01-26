$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/cluster'


class WorkerA
  include Sneakers::Worker
  from_queue 'downloads'

  def work(msg)
    sleep 1
    ack!
  end
end

class WorkerB
  include Sneakers::Worker
  from_queue 'downloads'

  workgroup :transactions

  def work(msg)
    sleep 1
    ack!
  end
end

Sneakers::Cluster.configure_workrgoups(
  default: {
    workers: 2
  },
  transactions: {
    workers: 1,
    share_threads: true,
    threads: 10
  }
)

Sneakers::Cluster.start(nil) # start all groups
