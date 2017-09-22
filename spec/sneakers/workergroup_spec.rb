require 'logger'
require 'spec_helper'
require 'sneakers'
require 'sneakers/workergroup'

class TestWorkerGroup
  include Sneakers::WorkerGroup
  def config
    {}
  end
end

describe Sneakers::WorkerGroup do
  describe "create_connection_or_nil" do
    before do
      Sneakers.configure(config)
    end

    let(:worker_group) { TestWorkerGroup.new }

    describe "with a connection in sneakers config" do
      let(:connection) { Bunny.new }
      let(:config) {
        {
          connection: connection
        }
      }

      it 'uses specified connection' do
        worker_group.send(:create_connection_or_nil).must_equal(connection)
      end
    end

    describe "without a connection in sneakers config" do
      let(:config) { {} }

      it 'returns nil' do
        worker_group.send(:create_connection_or_nil).must_be_nil
      end
    end
  end
end

