class Sneakers::Utils
  def self.make_worker_id(namespace)
    "worker-#{namespace}:#{'1'}:#{rand(36**6).floor.to_s(36)}"  # jid, worker id. include date.
  end

  def self.parse_workers(workerstring)
    missing_workers = []
    workers = (workerstring || '').split(',').map do |k|
      begin
        w = Sneakers::Utils.find_const_by_classname(k)
      rescue 
        missing_workers << k
      end
      w
    end.compact

    [workers, missing_workers]
  end

  # Finds and returns the constant that is identified by the passed in klassname.
  # If the klassname is deeply nested in multiple modules, it will iteratively
  # attempt to retrieve each nested module until it reaches the end.
  #
  # @param klassname {String}.  A String representation of a class name, like "Foo" or "Foo::Bar::Baz"
  # @return {Class}. A Class that is identified by the passed in klassname.
  def self.find_const_by_classname(klassname)
    current = Object
    modules = klassname.split("::")

    if modules.length > 1
      modules.each do |m|
        current = current.const_get(m)
      end
      
      return current
    else

      return Object.const_get(klassname)
    end
    
  end

end
