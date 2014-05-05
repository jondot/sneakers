require 'spec_helper'
require 'sneakers'
require 'timeout'
require 'sneakers/handlers/oneshot'
require 'sneakers/handlers/maxretry'


# Specific tests of the Handler implementations you can use to deal with job
# results. These tests only make sense with a worker that requires acking.

class HandlerTestWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true

  def work(msg)
    if msg.is_a?(StandardError)
      raise msg
    else
      msg
    end
  end
end

class TestPool
  def process(*args,&block)
    block.call
  end
end


describe 'Handlers' do
  let(:queue) { Object.new }
  let(:worker) { HandlerTestWorker.new(@queue, TestPool.new) }

  before(:each) do
    Sneakers.configure(:daemonize => true, :log => 'sneakers.log')
    Sneakers::Worker.configure_logger(Logger.new('/dev/null'))
    Sneakers::Worker.configure_metrics
  end

  describe 'Oneshot' do
    before(:each) do
      @channel = Object.new
      @opts = Object.new
      @handler = Sneakers::Handlers::Oneshot.new(@channel, @opts)

      @header = Object.new
      stub(@header).delivery_tag { 37 }
    end

    describe '#do_work' do
      it 'should work and handle acks' do
        mock(@channel).acknowledge(37, false)

        worker.do_work(@header, nil, :ack, @handler)
      end

      it 'should work and handle rejects' do
        mock(@channel).reject(37, false)

        worker.do_work(@header, nil, :reject, @handler)
      end

      it 'should work and handle requeues' do
        mock(@channel).reject(37, true)

        worker.do_work(@header, nil, :requeue, @handler)
      end

      it 'should work and handle user-land timeouts' do
        mock(@channel).reject(37, false)

        worker.do_work(@header, nil, :timeout, @handler)
      end

      it 'should work and handle user-land error' do
        mock(@channel).reject(37, false)

        worker.do_work(@header, nil, StandardError.new('boom!'), @handler)
      end

      it 'should work and handle noops' do
        worker.do_work(@header, nil, :wait, @handler)
      end
    end

  end

  describe 'Maxretry' do
    let(:max_retries) { nil }

    before(:each) do
      @channel = Object.new
      @opts = {
        :exchange => 'sneakers',
      }.tap do |opts|
        opts[:retry_max_times] = max_retries unless max_retries.nil?
      end

      @retry_exchange = Object.new
      @retry_queue = Object.new
      @error_exchange = Object.new
      @error_queue = Object.new

      mock(@channel).exchange('sneakers-retry',
                              :type => 'topic',
                              :durable => 'true').once { @retry_exchange }
      mock(@channel).queue('sneakers-retry',
                           :durable => 'true',
                           :arguments => {
                             :'x-dead-letter-exchange' => 'sneakers',
                             :'x-message-ttl' => 60000
                           }
                           ).once { @retry_queue }
      mock(@retry_queue).bind(@retry_exchange, :routing_key => '#')

      mock(@channel).exchange('sneakers-error',
                              :type => 'topic',
                              :durable => 'true').once { @error_exchange }
      mock(@channel).queue('sneakers-error',
                           :durable => 'true').once { @error_queue }
      mock(@error_queue).bind(@error_exchange, :routing_key => '#')

      @handler = Sneakers::Handlers::Maxretry.new(@channel, @opts)

      @header = Object.new
      stub(@header).delivery_tag { 37 }

      @props = {}
      @props_with_x_death = {
        :headers => {
          "x-death" => [
                        {
                          "reason" => "expired",
                          "queue" => "sneakers-retry",
                          "time" => Time.now,
                          "exchange" => "RawMail-retry",
                          "routing-keys" => ["RawMail"]
                        },
                        {
                          "reason" => "rejected",
                          "queue" => "sneakers",
                          "time" => Time.now,
                          "exchange" => "",
                          "routing-keys" => ["RawMail"]
                        }
                       ]
        },
        :delivery_mode => 1}
    end

    # it 'allows overriding the retry exchange name'
    # it 'allows overriding the error exchange name'
    # it 'allows overriding the retry timeout'

    describe '#do_work' do
      it 'should work and handle acks' do
        mock(@channel).acknowledge(37, false)

        worker.do_work(@header, @props, :ack, @handler)
      end

      describe 'rejects' do
        describe 'more retries ahead' do
          it 'should work and handle rejects' do
            mock(@channel).reject(37, false)

            worker.do_work(@header, @props_with_x_death, :reject, @handler)
          end
        end

        describe 'no more retries' do
          let(:max_retries) { 1 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(@channel).acknowledge(37, false)
            mock(@error_exchange).publish(:reject, :routing_key => '#')

            worker.do_work(@header, @props_with_x_death, :reject, @handler)
          end

        end
      end

      describe 'requeues' do
        it 'should work and handle requeues' do
          mock(@channel).reject(37, true)

          worker.do_work(@header, @props_with_x_death, :requeue, @handler)
        end

        describe 'no more retries left' do
          let(:max_retries) { 1 }

          it 'continues to reject with requeue' do
            mock(@channel).reject(37, true)

            worker.do_work(@header, @props_with_x_death, :requeue, @handler)
          end
        end

      end

      it 'should work and handle user-land timeouts' do
        mock(@channel).reject(37, false)

        worker.do_work(@header, @props, :timeout, @handler)
      end

      it 'should work and handle user-land error' do
        mock(@channel).reject(37, false)

        worker.do_work(@header, @props, StandardError.new('boom!'), @handler)
      end

      it 'should work and handle noops' do
        worker.do_work(@header, @props, :wait, @handler)
      end
    end

  end
end
