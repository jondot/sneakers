require 'spec_helper'
require 'sneakers'

module Foo
  class Bar
    include Sneakers::Worker
    from_queue 'defaults'
    
    def work(msg)
      ack!
    end
  end
end

class Biz
  include Sneakers::Worker
  from_queue 'defaults'

  def work(msg)
    ack!
  end
end

describe Sneakers::Utils do
  before do
    Sneakers.clear!
  end

  describe 'self' do
    
    # Ensures that a nested class like Foo::Bar above should be 
    # correctly identified by Sneakers as a worker.
    it "should be able to infer a class from a deeply nested class name" do
      res = Sneakers::Utils.find_const_by_classname("Foo::Bar")
      assert_equal res, Foo::Bar
    end

    # Ensures that a top-level class like Biz above should be 
    # correctly identified by Sneakers as a worker.
    it "should be able to infer a class from a top-level class name" do
      res = Sneakers::Utils.find_const_by_classname("Biz")
      assert_equal res, Biz
    end
  end
end
