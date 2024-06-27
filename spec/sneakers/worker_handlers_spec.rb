require 'spec_helper'
require 'sneakers'
require 'sneakers/handlers/oneshot'
require 'sneakers/handlers/maxretry'
require 'sneakers/handlers/expbackoff'
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

        mock(queue).bind(@requeue_exchange, :routing_key => '#')

        @handler = Sneakers::Handlers::Maxretry.new(channel, queue, @opts)
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
            _(@error_exchange.called).must_equal(true)
            _(@error_exchange.opts[:routing_key]).must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            _(data).wont_be_nil
            _(data['error']).must_equal('reject')
            _(data['num_attempts']).must_equal(2)
            _(@error_exchange.data).must_equal(:reject)
            _(data['properties'].to_json).must_equal(@props_with_x_death.to_json)
            _(Time.parse(data['failed_at'])).wont_be_nil
          end

          it 'counts the number of attempts using the count key' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @error_exchange.extend MockPublish
            worker.do_work(@header, props_with_x_death_count, :reject, @handler)
            _(@error_exchange.called).must_equal(true)
            _(@error_exchange.opts[:routing_key]).must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            _(data).wont_be_nil
            _(data['error']).must_equal('reject')
            _(data['num_attempts']).must_equal(4)
            _(@error_exchange.data).must_equal(:reject)
            _(data['properties'].to_json).must_equal(props_with_x_death_count.to_json)
            _(Time.parse(data['failed_at'])).wont_be_nil
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
            _(@error_exchange.called).must_equal(true)
            _(@error_exchange.opts[:routing_key]).must_equal('#')
            data = JSON.parse(@error_exchange.opts[:headers][:retry_info]) rescue nil
            _(data).wont_be_nil
            _(data['error']).must_equal('boom!')
            _(data['error_class']).must_equal(StandardError.to_s)
            _(data['backtrace']).wont_be_nil
            _(data['num_attempts']).must_equal(2)
            _(@error_exchange.data.to_s).must_equal('boom!')
            _(data['properties'].to_json).must_equal(@props_with_x_death.to_json)
            _(Time.parse(data['failed_at'])).wont_be_nil
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

    describe '.configure_queue' do
      before do
        mock(channel).prefetch(10)
        @mkbunny = Object.new
        @mkex = Object.new
        @mkworker = Object.new

        mock(@mkbunny).start {}
        mock(@mkbunny).create_channel{ channel }
        mock(Bunny).new(
          anything,
          hash_including(:vhost => '/', :heartbeat => 2)
        ){ @mkbunny }

        mock(channel).exchange("sneakers",
                               :type => :direct,
                               :durable => 'true', 
                               :auto_delete => false, 
                               :arguments => {}).once { @mkex }
      end

      describe 'use queue name for retry exchange' do
        before do
          Sneakers.clear!
          Sneakers.configure({
            :connection => nil,
            :ack => true,
            :heartbeat => 2,
            :vhost => '/',
            :exchange => "sneakers",
            :exchange_options => {
              :type => :direct,
              durable: 'true'
            },
            :queue_options => {
              :durable => 'true'
            },
            :handler => Sneakers::Handlers::Maxretry
          })
        end

        describe 'default settings' do
          before do
            mock(queue).bind(@requeue_exchange, :routing_key => '#')
            @worker_opts = Sneakers::CONFIG.merge({})
            stub(@mkworker).opts { @worker_opts }
          end

          let(:q) { Sneakers::Queue.new("downloads", @worker_opts) }

          it 'should configure queue with x-dead-letter-exchange' do
            mock(channel).queue("downloads", :durable => 'true', :auto_delete => false, :exclusive => false, :arguments => { :"x-dead-letter-exchange" => "downloads-retry" }).once { queue }
            mock(queue).bind(@mkex, :routing_key => "downloads")
            mock(queue).subscribe(:block => false, :manual_ack => true)

            q.subscribe(@mkworker)
          end
        end

        describe 'preserve other worker arguments' do
          before do
            mock(queue).bind(@requeue_exchange, :routing_key => '#')
            @worker_opts = Sneakers::CONFIG.merge({ :arguments => { 'x-arg' => 'value' } })
            stub(@mkworker).opts { @worker_opts }
          end

          let(:q) { Sneakers::Queue.new("downloads", @worker_opts) }

          it 'should configure queue with x-dead-letter-exchange and other args' do
            mock(channel).queue("downloads", :durable => 'true', :auto_delete => false, :exclusive => false, :arguments => { :"x-dead-letter-exchange" => "downloads-retry", :"x-arg" => 'value' }).once { queue }
            mock(queue).bind(@mkex, :routing_key => "downloads")
            mock(queue).subscribe(:block => false, :manual_ack => true)

            q.subscribe(@mkworker)
          end
        end
      end

      describe 'use globally configured retry exchange name' do
        before do
          Sneakers.clear!
          Sneakers.configure({
            :connection => nil,
            :ack => true,
            :heartbeat => 2,
            :vhost => '/',
            :exchange => "sneakers",
            :exchange_options => {
              :type => :direct,
              durable: 'true'
            },
            :queue_options => {
              :durable => 'true'
            },
            :handler => Sneakers::Handlers::Maxretry,
            :retry_exchange => "downloads-retry",
            :retry_error_exchange => "downloads-error",
            :retry_requeue_exchange => "downloads-retry-requeue"
          })
        end

        describe 'use global setup for worker' do
          before do
            mock(queue).bind(@requeue_exchange, :routing_key => 'uploads')
            @worker_opts = Sneakers::CONFIG.merge({ :retry_routing_key => "uploads" })
            stub(@mkworker).opts { @worker_opts }
          end

          let(:q) { Sneakers::Queue.new("uploads", @worker_opts) }

          it 'should configure queue with x-dead-letter-exchange (not use queue name)' do
            mock(channel).queue("uploads", :durable => 'true', :auto_delete => false, :exclusive => false, :arguments => { :"x-dead-letter-exchange" => "downloads-retry" }).once { queue }
            mock(queue).bind(@mkex, :routing_key => "uploads")
            mock(queue).subscribe(:block => false, :manual_ack => true)

            q.subscribe(@mkworker)
          end
        end

        describe 'skip retry and go to error queue' do
          before do
            mock(queue).bind(@requeue_exchange, :routing_key => 'uploads')
            @worker_opts = Sneakers::CONFIG.merge({ :retry_routing_key => "uploads", :arguments => { :"x-dead-letter-exchange" => "downloads-error" } })
            stub(@mkworker).opts { @worker_opts }
          end

          let(:q) { Sneakers::Queue.new("uploads", @worker_opts) }

          it 'should configure queue with x-dead-letter-exchange (not use queue name)' do
            mock(channel).queue("uploads", :durable => 'true', :auto_delete => false, :exclusive => false, :arguments => { :"x-dead-letter-exchange" => "downloads-error" }).once { queue }
            mock(queue).bind(@mkex, :routing_key => "uploads")
            mock(queue).subscribe(:block => false, :manual_ack => true)

            q.subscribe(@mkworker)
          end
        end
      end
    end
  end

  describe 'Expbackoff' do
    let(:max_retries) { 3 }
    let(:props_with_x_death_count) {
      {
        :headers => {
          'count' => 3,
          :backoff => 240,
          "x-death" => [
                        {
                          "count" => 1,
                          "reason" => "expired",
                          "queue" => "downloads-backoff-240",
                          "time" => Time.now,
                          "exchange" => "downloads-backoff",
                          "routing-keys" => ["downloads"]
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

      @backoff_exchange = Object.new
      @error_exchange = Object.new
      @requeue_exchange = Object.new

      @backoff_60_queue = Object.new
      @backoff_120_queue = Object.new
      @backoff_240_queue = Object.new
      @error_queue = Object.new

      mock(channel).exchange('downloads-backoff',
                             :type => 'headers',
                             :durable => 'true').once { @backoff_exchange }
      mock(channel).exchange('downloads-error',
                             :type => 'topic',
                             :durable => 'true').once { @error_exchange }
      mock(channel).exchange('downloads-retry-requeue',
                             :type => 'topic',
                             :durable => 'true').once { @requeue_exchange }

      mock(channel).queue('downloads-backoff-60',
                          :durable => 'true',
                          :arguments => {
                            :'x-dead-letter-exchange' => 'downloads-retry-requeue',
                            :'x-message-ttl' => 60000
                          }
                          ).once { @backoff_60_queue }
      mock(@backoff_60_queue).bind(@backoff_exchange, :arguments => {:backoff => 60})

      mock(channel).queue('downloads-backoff-120',
                          :durable => 'true',
                          :arguments => {
                            :'x-dead-letter-exchange' => 'downloads-retry-requeue',
                            :'x-message-ttl' => 120000
                          }
                          ).once { @backoff_120_queue }
      mock(@backoff_120_queue).bind(@backoff_exchange, :arguments => {:backoff => 120})

      mock(channel).queue('downloads-backoff-240',
                          :durable => 'true',
                          :arguments => {
                            :'x-dead-letter-exchange' => 'downloads-retry-requeue',
                            :'x-message-ttl' => 240000
                          }
                          ).once { @backoff_240_queue }
      mock(@backoff_240_queue).bind(@backoff_exchange, :arguments => {:backoff => 240})

      mock(channel).queue('downloads-error',
                          :durable => 'true').once { @error_queue }
      mock(@error_queue).bind(@error_exchange, :routing_key => '#')

      mock(queue).bind(@requeue_exchange, :routing_key => '#')

      @handler = Sneakers::Handlers::Expbackoff.new(channel, queue, @opts)

      @header = Object.new
      stub(@header).delivery_tag { 37 }

      @props = {}
      @props_with_x_death = {
        :headers => {
          'count' => 1,
          :backoff => 60,
          "x-death" => [
                        {
                          "count" => 1,
                          "reason" => "expired",
                          "queue" => "downloads-backoff-60",
                          "time" => Time.now,
                          "exchange" => "downloads-backoff",
                          "routing-keys" => ["downloads"]
                        }
                       ]
        },
        :delivery_mode => 1}
    end

    # it 'allows overriding the retry exchange name'
    # it 'allows overriding the error exchange name'
    # it 'allows overriding the retry timeout'

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
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @backoff_exchange.extend MockPublish
            worker.do_work(@header, @props_with_x_death, :reject, @handler)
          end
        end

        describe 'no more retries' do
          let(:max_retries) { 3 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @error_exchange.extend MockPublish
            @backoff_exchange.extend MockPublish
            worker.do_work(@header, props_with_x_death_count, :reject, @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts.must_equal({ :routing_key => '#' })
            data = JSON.parse(@error_exchange.data)
            data['error'].must_equal('reject')
            data['num_attempts'].must_equal(4)
            data['payload'].must_equal(Base64.encode64(:reject.to_s))
            data['properties'].must_equal(Base64.encode64(props_with_x_death_count.to_json))
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
          let(:max_retries) { 3 }

          it 'continues to reject with requeue' do
            mock(channel).reject(37, true)

            worker.do_work(@header, @props_with_x_death, :requeue, @handler)
          end
        end

      end

      describe 'timeouts' do
        describe 'more retries ahead' do
          it 'should reject the message' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)

            @backoff_exchange.extend MockPublish
            worker.do_work(@header, @props_with_x_death, :timeout, @handler)
          end
        end

        describe 'no more retries left' do
          let(:max_retries) { 3 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)
            @error_exchange.extend MockPublish
            @backoff_exchange.extend MockPublish

            worker.do_work(@header, props_with_x_death_count, :timeout, @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts.must_equal({ :routing_key => '#' })
            data = JSON.parse(@error_exchange.data)
            data['error'].must_equal('timeout')
            data['num_attempts'].must_equal(4)
            data['payload'].must_equal(Base64.encode64(:timeout.to_s))
            data['properties'].must_equal(Base64.encode64(props_with_x_death_count.to_json))
            Time.parse(data['failed_at']).wont_be_nil
          end
        end
      end

      describe 'exceptions' do
        describe 'more retries ahead' do
          it 'should reject the message' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)
            @backoff_exchange.extend MockPublish

            worker.do_work(@header, @props_with_x_death, StandardError.new('boom!'), @handler)
          end
        end

        describe 'no more retries left' do
          let(:max_retries) { 3 }

          it 'sends the rejection to the error queue' do
            mock(@header).routing_key { '#' }
            mock(channel).acknowledge(37, false)
            @error_exchange.extend MockPublish
            @backoff_exchange.extend MockPublish

            worker.do_work(@header, props_with_x_death_count, StandardError.new('boom!'), @handler)
            @error_exchange.called.must_equal(true)
            @error_exchange.opts.must_equal({ :routing_key => '#' })
            data = JSON.parse(@error_exchange.data)
            data['error'].must_equal('boom!')
            data['error_class'].must_equal(StandardError.to_s)
            data['backtrace'].wont_be_nil
            data['num_attempts'].must_equal(4)
            data['payload'].must_equal(Base64.encode64('boom!'))
            data['properties'].must_equal(Base64.encode64(props_with_x_death_count.to_json))
            Time.parse(data['failed_at']).wont_be_nil
          end
        end
      end

      it 'should work and handle user-land error' do
        mock(@header).routing_key { '#' }
        mock(channel).acknowledge(37, false)
        @backoff_exchange.extend MockPublish

        worker.do_work(@header, @props, StandardError.new('boom!'), @handler)
      end

      it 'should work and handle noops' do
        @backoff_exchange.extend MockPublish
        worker.do_work(@header, @props, :wait, @handler)
      end

      # Since we encode in json, we want to make sure if the actual payload is
      # json, then it's something you can get back out.
      describe 'JSON payloads' do
        let(:max_retries) { 3 }

        it 'properly encodes the json payload' do
          mock(@header).routing_key { '#' }
          mock(channel).acknowledge(37, false)
          @error_exchange.extend MockPublish

          payload = {
            data: 'hello',
            response: :timeout
          }
          worker.do_work(@header, props_with_x_death_count, payload.to_json, @handler)
          @error_exchange.called.must_equal(true)
          @error_exchange.opts.must_equal({ :routing_key => '#' })
          data = JSON.parse(@error_exchange.data)
          data['error'].must_equal('timeout')
          data['num_attempts'].must_equal(4)
          data['payload'].must_equal(Base64.encode64(payload.to_json))
          data['properties'].must_equal(Base64.encode64(props_with_x_death_count.to_json))
        end

      end

    end
  end
end
