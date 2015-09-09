class Sneakers::Utils
  def self.make_worker_id(namespace)
    "worker-#{namespace}:#{'1'}:#{rand(36**6).floor.to_s(36)}"  # jid, worker id. include date.
  end
  def self.parse_workers(workerstring)
    missing_workers = []
    workers = (workerstring || '').split(',').map do |k|
      begin
        w = Kernel.const_get(k)
      rescue
        missing_workers << k
      end
      w
    end.compact

    [workers, missing_workers]
  end
end
