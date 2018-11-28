require 'spec_helper'
require 'sneakers'
require 'sneakers/handlers/oneshot'
require 'sneakers/handlers/maxretry'
require 'sneakers/handlers/ratelimiter'
require 'json'


# Specific tests of the Handler implementations you can use to deal with job
# results. These tests only make sense with a worker that requires acking.

class HandlerTestWorker
  include Sneakers::Worker
  from_queue 'defaults',
             :ack => true

  def work(msg)
    if msg.is_a?(StandardError)
      raise msg
    elsif msg.is_a?(String)
      hash = maybe_json(msg)
      if hash.is_a?(Hash)
        hash['response'].to_sym
      else
        hash
      end
    else
      msg
    end
  end

  def maybe_json(string)
    JSON.parse(string)
  rescue
    string
  end
end

TestPool ||= Concurrent::ImmediateExecutor

describe 'Handlers' do
  let(:channel) { Object.new }
  let(:queue) { Object.new }
  let(:worker) { HandlerTestWorker.new(@queue, TestPool.new) }

  before(:each) do
    Sneakers.configure(:daemonize => true, :log => 'sneakers.log')
    Sneakers::Worker.configure_logger(Logger.new('/dev/null'))
    Sneakers::Worker.configure_metrics
  end

  describe 'Oneshot' do
    before(:each) do
      @opts = Object.new
      @handler = Sneakers::Handlers::Oneshot.new(channel, queue, @opts)

      @header = Object.new
      stub(@header).delivery_tag { 37 }
    end

    describe '#do_work' do
      it 'should work and handle acks' do
        mock(channel).acknowledge(37, false)

        worker.do_work(@header, nil, :ack, @handler)
      end

      it 'should work and handle rejects' do
        mock(channel).reject(37, false)

        worker.do_work(@header, nil, :reject, @handler)
      end

      it 'should work and handle requeues' do
        mock(channel).reject(37, true)

        worker.do_work(@header, nil, :requeue, @handler)
      end

      it 'should work and handle user code error' do
        mock(channel).reject(37, false)

        worker.do_work(@header, nil, StandardError.new('boom!'), @handler)
      end

      it 'should work and handle noops' do
        worker.do_work(@header, nil, :wait, @handler)
      end
    end

  end

  describe 'Maxretry' do
    let(:max_retries) { nil }
    let(:props_with_x_death_count) {
      {
        :headers => {
          "x-death" => [
                        {
                          "count" => 3,
                          "reason" => "expired",
                          "queue" => "downloads-retry",
                          "time" => Time.now,
                          "exchange" => "RawMail-retry",
                          "routing-keys" => ["RawMail"]
                        },
                        {
                          "count" => 3,
                          "reason" => "rejected",
                          "queue" => "downloads",
                          "time" => Time.now,
                          "exchange" => "",
                          "routing-keys" => ["RawMail"]
                        }
                       ]
        },
        :delivery_mode => 1
      }
    }

    before(:each) do
      @opts = {
        :exchange => 'sneakers',
        :queue_options => {
          :durable => 'true',
        }
      }.tap do |opts|
        opts[:retry_max_times] = max_retries unless max_retries.nil?
      end

      mock(queue).name { 'downloads' }

      @retry_exchange = Object.new
      @error_exchange = Object.new
      @requeue_exchange = Object.new

      @retry_queue = Object.new
      @error_queue = Object.new

      mock(channel).exchange('downloads-retry',
                             :type => 'topic',
                             :durable => 'true').once { @retry_exchange }
      mock(channel).exchange('downloads-error',
                             :type => 'topic',
                             :durable => 'true').once { @error_exchange }
      mock(channel).exchange('downloads-retry-requeue',
                             :type => 'topic',
                             :durable => 'true').once { @requeue_exchange }

      mock(channel).queue('downloads-retry',
                          :durable => 'true',
                          :arguments => {
                            :'x-dead-letter-exchange' => 'downloads-retry-requeue',
                            :'x-message-ttl' => 60000
                          }
                          ).once { @retry_queue }
      mock(@retry_queue).bind(@retry_exchange, :routing_key => '#')

      mock(channel).queue('downloads-error',
                          :durable => 'true').once { @error_queue }
      mock(@error_queue).bind(@error_exchange, :routing_key => '#')

      mock(queue).bind(@requeue_exchange, :routing_key => '#')

      @handler = Sneakers::Handlers::Maxretry.new(channel, queue, @opts)

      @header = Object.new
      stub(@header).delivery_tag { 37 }

      @props = {}
      @props_with_x_death = {
        :headers => {
          "x-death" => [
                        {
                          "reason" => "expired",
                          "queue" => "downloads-retry",
                          "time" => Time.now,
                          "exchange" => "RawMail-retry",
                          "routing-keys" => ["RawMail"]
                        },
                        {
                          "reason" => "rejected",
                          "queue" => "downloads",
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

    describe '#do_work' do
      before do
        @now = Time.now
      end

      # Used to stub out the publish method args. Sadly RR doesn't support
      # this, only proxying existing methods.
      module MockPublish
        attr_reader :data, :opts, :called

        def publish(data, opts)
          @data = data
          @opts = opts
          @called = true
        end
      end

      it 'should work and handle acks' do
        mock(channel).acknowledge(37, false)

        worker.do_work(@header, @props, :ack, @handler)
      end

      describe 'rejects' do
        describe 'more retries ahead' do
          it 'should work and handle rejects' do
            mock(channel).reject(37, false)

            worker.do_work(@header, @props_with_x_death, :reject, @handler)
          end
        end

        describe 'no more retries' do
          let(:max_retries) { 1 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @error_exchange.extend MockPublish
            worker.do_work(@header, @props_with_x_death, :reject, @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts[:routing_key].must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            data.wont_be_nil
            data['error'].must_equal('reject')
            data['num_attempts'].must_equal(2)
            @error_exchange.data.must_equal(:reject)
            data['properties'].to_json.must_equal(@props_with_x_death.to_json)
            Time.parse(data['failed_at']).wont_be_nil
          end

          it 'counts the number of attempts using the count key' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @error_exchange.extend MockPublish
            worker.do_work(@header, props_with_x_death_count, :reject, @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts[:routing_key].must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            data.wont_be_nil
            data['error'].must_equal('reject')
            data['num_attempts'].must_equal(4)
            @error_exchange.data.must_equal(:reject)
            data['properties'].to_json.must_equal(props_with_x_death_count.to_json)
            Time.parse(data['failed_at']).wont_be_nil
          end

        end
      end

      describe 'requeues' do
        it 'should work and handle requeues' do
          mock(channel).reject(37, true)

          worker.do_work(@header, @props_with_x_death, :requeue, @handler)
        end

        describe 'no more retries left' do
          let(:max_retries) { 1 }

          it 'continues to reject with requeue' do
            mock(channel).reject(37, true)

            worker.do_work(@header, @props_with_x_death, :requeue, @handler)
          end
        end

      end

      describe 'exceptions' do
        describe 'more retries ahead' do
          it 'should reject the message' do
            mock(channel).reject(37, false)

            worker.do_work(@header, @props_with_x_death, StandardError.new('boom!'), @handler)
          end
        end

        describe 'no more retries left' do
          let(:max_retries) { 1 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)
            @error_exchange.extend MockPublish

            worker.do_work(@header, @props_with_x_death, StandardError.new('boom!'), @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts[:routing_key].must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            data.wont_be_nil
            data['error'].must_equal('boom!')
            data['error_class'].must_equal(StandardError.to_s)
            data['backtrace'].wont_be_nil
            data['num_attempts'].must_equal(2)
            @error_exchange.data.to_s.must_equal('boom!')
            data['properties'].to_json.must_equal(@props_with_x_death.to_json)
            Time.parse(data['failed_at']).wont_be_nil
          end
        end
      end

      it 'should work and handle user-land error' do
        mock(channel).reject(37, false)

        worker.do_work(@header, @props, StandardError.new('boom!'), @handler)
      end

      it 'should work and handle noops' do
        worker.do_work(@header, @props, :wait, @handler)
      end
    end
  end

  describe 'RateLimiter' do
    let(:queue_name) {'defaults'}
    let(:overflow_queue_name) {"#{queue_name}-overflow"}
    let(:rate_limit_queue_name) {"#{queue_name}-rate_limit"}
    let(:rate_limit_exchange) {Object.new}
    let(:rate_limit_exchange_name) {'rate_limit'}
    let(:decorated_handler) {Object.new}
    let(:opts) { {rate_limiter_decorated_handler_func: -> (*_args) {decorated_handler}}  }
    let(:header) {Object.new}
    let(:handler) {Sneakers::Handlers::RateLimiter.new(channel, queue, opts)}
    let(:metadata) {{}}

    before(:each) do
      rate_limit_queue = Object.new
      overflow_queue = Object.new

      mock(rate_limit_queue).bind(rate_limit_exchange, :routing_key => queue_name)
      mock(overflow_queue).bind(rate_limit_exchange, :routing_key => overflow_queue_name)

      mock(queue).name {queue_name}
      mock(channel).exchange(anything, anything).times(2) {rate_limit_exchange}

      mock(channel).queue(overflow_queue_name, anything) {overflow_queue}
      mock(channel).queue(rate_limit_queue_name, anything) {rate_limit_queue}

      stub(header).delivery_tag { 37 }
    end

    describe '#do_work' do

      before(:each) do
        mock(handler).before_work(anything, anything, anything) {true}
      end

      it 'should forward ack to attached handler' do
        mock(decorated_handler).acknowledge(header, metadata, :ack)
        worker.do_work(header, metadata, :ack, handler)
      end

      it 'should forward reject to attached handler' do
        mock(decorated_handler).reject(header, metadata, :reject, false)
        worker.do_work(header, metadata, :reject, handler)
      end

      it 'should forward requeue message to attached handler' do
        mock(decorated_handler).reject(header, metadata, :requeue, true)
        worker.do_work(header, metadata, :requeue, handler)
      end

      it 'should forward errors to attached handler' do
        error = StandardError.new('boom!')
        mock(decorated_handler).error(header, metadata, error, error)
        worker.do_work(header, metadata, error, handler)
      end

      it 'should forward noops' do
        mock(decorated_handler).noop(header, metadata, :wait)
        worker.do_work(header, metadata, :wait, handler)
      end
    end

    describe 'message_went_through_rate_limit_queue?' do
      describe 'when the headers are missing' do
        it 'returns false' do
          headers = nil

          result = handler.message_went_through_rate_limit_queue?(headers)

          result.must_equal(false)
        end
      end

      describe 'when the x-death is missing' do
        it 'returns false' do
          headers = {
            'x-death' => nil
          }

          result = handler.message_went_through_rate_limit_queue?(headers)

          result.must_equal(false)
        end
      end

      describe 'when the headers are present' do
        describe 'when the message did not go through the rate limit exchange' do
          it 'returns false' do
            headers = {
              'x-death' => [
                {
                  'exchange' => 'different_exchange',
                  'queue' => rate_limit_queue_name
                }
              ]
            }

            result = handler.message_went_through_rate_limit_queue?(headers)

            result.must_equal(false)
          end
        end

        describe 'when the message went through the rate limit exchange but a different queue' do
          it 'returns false' do
            headers = {
              'x-death' => [
                {
                  'exchange' => rate_limit_exchange_name,
                  'queue' => 'different_queue'
                }
              ]
            }

            result = handler.message_went_through_rate_limit_queue?(headers)

            result.must_equal(false)
          end
        end

        describe 'when message went through the rate limit exchange and rate limit queue' do
          it 'returns true' do
            headers = {
              'x-death' => [
                {
                  'exchange' => rate_limit_exchange_name,
                  'queue' => rate_limit_queue_name
                }
              ]
            }

            result = handler.message_went_through_rate_limit_queue?(headers)

            result.must_equal(true)
          end
        end
      end
    end

    describe 'before_work' do
      describe 'message went through rate limit exchange' do
        it 'should allow work to proceed' do
          props = {
            headers: {
              'x-death' => [
                {
                  'exchange' => rate_limit_exchange_name,
                  'queue' => rate_limit_queue_name
                }
              ]
            }
          }
          result = handler.before_work(nil, props, nil)
          result.must_equal(true)
        end
      end

      describe 'message is new (did not go through rate limit exchange)' do
        let(:message_) {'message'}
        let(:props) {{headers: {}}}
        let(:headers) {props[:headers]}

        it 'should not allow the message to be processed' do
          mock(channel).confirm_select
          stub(rate_limit_exchange).publish(message_, :headers => headers, :routing_key => queue_name)
          mock(channel).wait_for_confirms {true}
          stub(decorated_handler).acknowledge(nil, props, message_)

          result = handler.before_work(nil, props, message_)

          result.must_equal(false)
        end

        it 'should acknowledge the message' do
          mock(channel).confirm_select
          stub(rate_limit_exchange).publish(message_, :headers => headers, :routing_key => queue_name)
          mock(channel).wait_for_confirms {true}
          mock(decorated_handler).acknowledge(nil, props, message_)

          result = handler.before_work(nil, props, message_)
        end

        it 'should forward the message to the rate limit exchange' do
          mock(channel).confirm_select
          mock(rate_limit_exchange).publish(message_, :headers => headers, :routing_key => queue_name)
          mock(channel).wait_for_confirms {true}
          stub(decorated_handler).acknowledge(nil, props, message_)

          result = handler.before_work(nil, props, message_)
        end

        describe 'when the rate limit queue is full' do
          it 'should send the message to the overflow waiting queue' do
            mock(handler).send_to_rate_limit_queue(message_, headers) {false}
            mock(rate_limit_exchange).publish(message_, :headers => headers, :routing_key => overflow_queue_name)
            stub(decorated_handler).acknowledge(nil, props, message_)

            result = handler.before_work(nil, props, message_)
          end

          it 'should acknowledge the message' do
            mock(handler).send_to_rate_limit_queue(message_, headers) {false}
            stub(rate_limit_exchange).publish(message_, :headers => headers, :routing_key => overflow_queue_name)
            mock(decorated_handler).acknowledge(nil, props, message_)

            result = handler.before_work(nil, props, message_)
          end
        end
      end
    end
  end
end
