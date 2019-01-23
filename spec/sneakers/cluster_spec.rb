require 'spec_helper'
require 'sneakers'
require 'sneakers/cluster'

describe Sneakers::Cluster do
  describe "#start" do
    before do
      Sneakers.configure(log: Logger.new(STDOUT))
      Sneakers.logger.level = Logger::WARN
      stub(Sneakers::Cluster).fork { |block| block.call }
      any_instance_of(Sneakers::Runner) { |runner| stub(runner).run }
      stub(Sneakers::CONFIG[:hooks][:before_fork]).call
    end

    it "calls Sneakers::Runner#run" do
      fake_runner = mock(Object.new).run
      stub(Sneakers::Runner).new { fake_runner }
      Sneakers::Cluster.start(:test)
    end

    it "calls fork hook" do
      called = :no
      Sneakers::Cluster.after_fork { called = :yes }
      Sneakers::Cluster.start(:test)
      called.must_equal :yes
    end

    it "applies workgroup config" do
      mock(Sneakers::Cluster).apply_workgroup_config!
      Sneakers::Cluster.start(:test)
    end

    it "sets @current_workgroup" do
      Sneakers::Cluster.start(:test)
      Sneakers::Cluster.current_workgroup.must_equal :test
      Sneakers::Cluster.start(:test2)
      Sneakers::Cluster.current_workgroup.must_equal :test2
    end
  end

  describe "#configure_workrgoups" do
    before do
      Sneakers.clear!
      Sneakers::Cluster.configure_workrgoups(
        test1: { somekey: :someval },
        test2: { somekey: :someval2 }
      )
    end

    it "does not change config if workgroup not set" do
      before = Sneakers::CONFIG
      stub(Sneakers::Cluster).current_workgroup { nil }
      Sneakers::Cluster.apply_workgroup_config!
      Sneakers::CONFIG.must_equal before
    end

    it "applies config when called" do
      stub(Sneakers::Cluster).current_workgroup { :test1 }
      Sneakers::Cluster.apply_workgroup_config!
      Sneakers::CONFIG[:somekey].must_equal :someval
    end

    it "scopes config by workgroups" do
      stub(Sneakers::Cluster).current_workgroup { :test2 }
      Sneakers::Cluster.apply_workgroup_config!
      Sneakers::CONFIG[:somekey].must_equal :someval2
    end
  end
end
