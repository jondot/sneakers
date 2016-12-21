require 'timeout'

module Sneakers
  class WorkerTimeout < Timeout::Error; end
end
