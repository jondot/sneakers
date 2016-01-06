require 'spec_helper'
require 'sneakers'
require 'sneakers/runner'
require 'fixtures/integration_worker'
require 'fixtures/maxretry_worker'

require "rabbitmq/http/client"

REQUEUING_WAIT_TIME = 1

describe "integration" do
  describe 'first' do
    before :each do
      skip unless ENV['INTEGRATION']
      prepare
    end

    def prepare
      # clean up all integration queues; admin interface must be installed
      # in integration env
      begin
        admin = RabbitMQ::HTTP::Client.new("http://127.0.0.1:15672/", username: "guest", password: "guest")
        qs = admin.list_queues
        qs.each do |q|
          name = q.name
          if name.start_with? 'integration_'
            admin.delete_queue('/', name)
            integration_log "cleaning up #{name}."
          end
        end
      rescue
        puts "Rabbitmq admin seems to not exist? you better be running this on Travis or Docker. proceeding.\n#{$!}"
      end

      Sneakers.clear!
      Sneakers.configure
      Sneakers.logger.level = Logger::ERROR

      # configure integration worker on a random generated queue
      random_queue = "integration_#{rand(10**36).to_s(36)}"

      @redis = Redis.new
      @redis.del(random_queue)
      IntegrationWorker.from_queue(random_queue)
    end

    def assert_all_accounted_for(opts)
      integration_log 'waiting for publishes to stabilize (5s).'
      sleep 5

      integration_log "polling for changes (max #{opts[:within_sec]}s)."
      pid = opts[:pid]
      opts[:within_sec].times do
        sleep 1
        count = @redis.get(opts[:queue]).to_i
        if count == opts[:jobs]
          integration_log "#{count} jobs accounted for successfully."
          Process.kill("TERM", pid)
          sleep 1
          return
        end
      end

      integration_log "failed test. killing off workers."
      Process.kill("TERM", pid)
      sleep 1
      fail "incomplete!"
    end

    it 'should pull down 100 jobs from a real queue' do
      job_count = 100

      pid = start_worker(IntegrationWorker)

      integration_log "publishing..."
      p = Sneakers::Publisher.new
      job_count.times do |i|
        p.publish("m #{i}", to_queue: IntegrationWorker.queue_name)
      end

      assert_all_accounted_for(
         queue: IntegrationWorker.queue_name,
         pid: pid,
         within_sec: 15,
         jobs: job_count,
      )
    end

  end

  describe 'worker with maxretry handler' do
    let(:rabbitmq_client) do
      RabbitMQ::HTTP::Client.new('http://guest:guest@127.0.0.1:15672/')
    end
    let(:redis) { Redis.new }
    let(:queue_name) { "integration_#{rand(10**36).to_s(36)}" }
    let(:exchange_name) { "integration_#{rand(10**36).to_s(36)}" }

    before :each do
      skip unless ENV['INTEGRATION']

      begin
        rabbitmq_client.overview
      rescue
        puts 'Rabbitmq admin seems to not exist? You better be running this on'\
          "Travis or Docker. proceeding.\n#{$ERROR_INFO}"
        skip
      end

      begin
        redis.info
      rescue
        puts 'Redis seems to not exist? You better be running this on'\
          'Travis or Docker.'
        skip
      end

      cleanup_rabbitmq(rabbitmq_client)
      cleanup_redis(redis)
      prepare_sneakers(exchange: exchange_name)

      worker.from_queue(queue_name, worker_opts)
      @worker_pid = start_worker(worker)
    end

    after :each do
      Process.kill('TERM', @worker_pid)

      cleanup_rabbitmq(rabbitmq_client)
      cleanup_redis(redis)
    end

    describe 'with defaults for maxretry handler' do
      let(:worker) { AlwaysAckWorker }
      let(:worker_opts) do
        {
          handler:         Sneakers::Handlers::Maxretry,
          retry_max_times: 2,
          retry_timeout:   100,
          arguments: {
            'x-dead-letter-exchange' => "#{queue_name}-retry"
          }
        }
      end

      it 'creates the required exchanges' do
        expected_exchange_names = [
          exchange_name,
          "#{queue_name}-error",
          "#{queue_name}-retry",
          "#{queue_name}-retry-requeue"
        ]
        exchange_names = rabbitmq_client.list_exchanges.map(&:name)

        expected_exchange_names.each do |expected_exchange_name|
          assert_includes(exchange_names, expected_exchange_name)
        end
      end

      it 'creates the required queues' do
        expected_queue_names = [
          queue_name,
          "#{queue_name}-error",
          "#{queue_name}-retry"
        ]
        queue_names = rabbitmq_client.list_queues.map(&:name)

        expected_queue_names.each do |expected_queue_name|
          assert_includes(queue_names, expected_queue_name)
        end
      end

      describe 'when worker allways fails' do
        let(:worker) { AlwaysRejectWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has a message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue("#{queue_name}-error")

          refute_nil(message.first)
        end

        it 'has been retried twice' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue("#{queue_name}-error")

          assert_equal(JSON.load(message[2])['num_attempts'], 3)
        end
      end

      describe 'when worker fails once' do
        let(:worker) { RejectOnceWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has no message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue("#{queue_name}-error")

          assert_nil(message.first)
        end

        it 'consumes the requeued message' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = redis.get(queue_name)

          refute_nil(message)
        end

        it 'it has been routed to retry exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(message_headers, queue_name)

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('rejected', consumer_x_death_array.first['reason'])
          assert_equal(exchange_name, consumer_x_death_array.first['exchange'])
        end

        it 'it has been routed to requeue exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(
            message_headers,
            "#{queue_name}-retry"
          )

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('expired', consumer_x_death_array.first['reason'])
          assert_equal(
            "#{queue_name}-retry",
            consumer_x_death_array.first['exchange']
          )
        end
      end
    end

    describe 'with customized config for maxretry handler' do
      let(:worker) { AlwaysAckWorker }
      let(:retry_exchange) { 'integration_retry_exchange' }
      let(:retry_error_exchange) { 'integration_error_exchange' }
      let(:retry_requeue_exchange) { 'integration_requeue_exchange' }
      let(:retry_routing_key) { 'foo' }
      let(:requeue_routing_key) { 'bar' }
      let(:error_routing_key) { 'baz' }
      let(:retry_queue_name) { 'integration_retry_queue' }
      let(:error_queue_name) { 'integration_error_queue' }

      let(:worker_opts) do
        {
          handler:                Sneakers::Handlers::Maxretry,
          retry_max_times:        2,
          retry_timeout:          100,
          retry_exchange:         retry_exchange,
          retry_error_exchange:   retry_error_exchange,
          retry_requeue_exchange: retry_requeue_exchange,
          retry_routing_key:      retry_routing_key,
          requeue_routing_key:    requeue_routing_key,
          error_routing_key:      error_routing_key,
          retry_queue_name:       retry_queue_name,
          error_queue_name:       error_queue_name,
          arguments: {
            'x-dead-letter-exchange'    => retry_exchange,
            'x-dead-letter-routing-key' => retry_routing_key
          }
        }
      end

      it 'creates the required exchanges' do
        expected_exchange_names = [
          exchange_name,
          retry_exchange,
          retry_error_exchange,
          retry_requeue_exchange
        ]
        exchange_names = rabbitmq_client.list_exchanges.map(&:name)

        expected_exchange_names.each do |expected_exchange_name|
          assert_includes(exchange_names, expected_exchange_name)
        end
      end

      it 'creates the required queues' do
        expected_queue_names = [
          queue_name,
          retry_queue_name,
          error_queue_name
        ]
        queue_names = rabbitmq_client.list_queues.map(&:name)

        expected_queue_names.each do |expected_queue_name|
          assert_includes(queue_names, expected_queue_name)
        end
      end

      describe 'when worker allways fails' do
        let(:worker) { AlwaysRejectWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has a message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          refute_nil(message.first)
        end

        it 'has been retried twice' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          assert_equal(3, JSON.load(message[2])['num_attempts'])
        end
      end

      describe 'when worker fails once' do
        let(:worker) { RejectOnceWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has no message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          assert_nil(message.first)
        end

        it 'consumes the requeued message' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = redis.get(queue_name)

          refute_nil(message)
        end

        it 'it has been routed to retry exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(message_headers, queue_name)

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('rejected', consumer_x_death_array.first['reason'])
          assert_equal(exchange_name, consumer_x_death_array.first['exchange'])
        end

        it 'it has been routed to requeue exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(
            message_headers,
            retry_queue_name
          )

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('expired', consumer_x_death_array.first['reason'])
          assert_equal(retry_exchange, consumer_x_death_array.first['exchange'])
        end
      end
    end

    describe 'with config for only one additional exchange' do
      let(:worker) { AlwaysAckWorker }
      let(:retry_error_exchange) { 'integration_error_exchange' }
      let(:retry_routing_key) { 'foo' }
      let(:requeue_routing_key) { 'bar' }
      let(:error_routing_key) { 'baz' }
      let(:retry_queue_name) { 'integration_retry_queue' }
      let(:error_queue_name) { 'integration_error_queue' }

      let(:worker_opts) do
        {
          handler:                Sneakers::Handlers::Maxretry,
          retry_max_times:        2,
          retry_timeout:          100,
          retry_exchange:         exchange_name,
          retry_error_exchange:   retry_error_exchange,
          retry_requeue_exchange: exchange_name,
          retry_routing_key:      retry_routing_key,
          requeue_routing_key:    requeue_routing_key,
          error_routing_key:      error_routing_key,
          retry_queue_name:       retry_queue_name,
          error_queue_name:       error_queue_name,
          exchange_options:       {
            type: :topic
          },
          arguments:              {
            'x-dead-letter-exchange'    => exchange_name,
            'x-dead-letter-routing-key' => retry_routing_key
          }
        }
      end

      it 'creates the required exchanges' do
        expected_exchange_names = [
          exchange_name,
          retry_error_exchange
        ]
        exchange_names = rabbitmq_client.list_exchanges.map(&:name)

        expected_exchange_names.each do |expected_exchange_name|
          assert_includes(exchange_names, expected_exchange_name)
        end
      end

      it 'creates the required queues' do
        expected_queue_names = [
          queue_name,
          retry_queue_name,
          error_queue_name
        ]
        queue_names = rabbitmq_client.list_queues.map(&:name)

        expected_queue_names.each do |expected_queue_name|
          assert_includes(queue_names, expected_queue_name)
        end
      end

      describe 'when worker allways fails' do
        let(:worker) { AlwaysRejectWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name,
            exchange_options: {
              type: :topic
            }
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has a message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          refute_nil(message.first)
        end

        it 'has been retried twice' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          assert_equal(3, JSON.load(message[2])['num_attempts'])
        end
      end

      describe 'when worker fails once' do
        let(:worker) { RejectOnceWorker }

        before do
          Sneakers::Publisher.new(
            exchange: exchange_name,
            exchange_options: {
              type: :topic
            }
          ).publish(
            'foo',
            routing_key: queue_name
          )
        end

        it 'has no message in the error queue' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = get_message_from_queue(error_queue_name)

          assert_nil(message.first)
        end

        it 'consumes the requeued message' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = redis.get(queue_name)

          refute_nil(message)
        end

        it 'it has been routed to retry exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(message_headers, queue_name)

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('rejected', consumer_x_death_array.first['reason'])
          assert_equal(exchange_name, consumer_x_death_array.first['exchange'])
        end

        it 'it has been routed to requeue exchange once' do
          # wait for failing message
          sleep REQUEUING_WAIT_TIME

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death_array = x_death_array(
            message_headers,
            retry_queue_name
          )

          assert_equal(
            1,
            consumer_x_death_array.first['count'] ||
            consumer_x_death_array.count
          )
          assert_equal('expired', consumer_x_death_array.first['reason'])
          assert_equal(exchange_name, consumer_x_death_array.first['exchange'])
        end
      end
    end
  end
end
