require 'spec_helper'
require 'sneakers'
require 'sneakers/runner'
require 'fixtures/integration_worker'
require 'fixtures/maxretry_worker'

require "rabbitmq/http/client"


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
      let(:worker) { MaxretryWorker }
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
        let(:worker) { FailingMaxretryWorker }

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
          sleep 1

          message = get_message_from_queue("#{queue_name}-error")

          refute_nil(message.first)
        end

        it 'has been retried twice' do
          # wait for failing message
          sleep 1

          message = get_message_from_queue("#{queue_name}-error")

          # Hmmmmm... should be 2
          assert_equal(JSON.load(message[2])['num_attempts'], 3)
        end
      end

      describe 'when worker fails once' do
        let(:worker) { RetryOnceWorker }

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
          sleep 1

          message = get_message_from_queue("#{queue_name}-error")

          assert_nil(message.first)
        end

        it 'consumes the requeued message' do
          # wait for failing message
          sleep 1

          message = redis.get(queue_name)

          refute_nil(message)
        end

        it 'it has been routed to retry exchange once' do
          # wait for failing message
          sleep 1

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death = message_headers['x-death'].detect do |x|
            x['queue'] == queue_name
          end

          assert_equal(consumer_x_death['count'], 1)
          assert_equal(consumer_x_death['reason'], 'rejected')
          assert_equal(consumer_x_death['exchange'], exchange_name)
        end

        it 'it has been routed to requeue exchange once' do
          # wait for failing message
          sleep 1

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death = message_headers['x-death'].detect do |x|
            x['queue'] == "#{queue_name}-retry"
          end

          assert_equal(consumer_x_death['count'], 1)
          assert_equal(consumer_x_death['reason'], 'expired')
          assert_equal(consumer_x_death['exchange'], "#{queue_name}-retry")
        end
      end
    end

    describe 'with customized config for maxretry handler' do
      let(:worker) { MaxretryWorker }
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
        let(:worker) { FailingMaxretryWorker }

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
          sleep 1

          message = get_message_from_queue(error_queue_name)

          refute_nil(message.first)
        end

        it 'has been retried twice' do
          # wait for failing message
          sleep 1

          message = get_message_from_queue(error_queue_name)

          # Hmmmmm... should be 2
          assert_equal(JSON.load(message[2])['num_attempts'], 3)
        end
      end

      describe 'when worker fails once' do
        let(:worker) { RetryOnceWorker }

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
          sleep 1

          message = get_message_from_queue(error_queue_name)

          assert_nil(message.first)
        end

        it 'consumes the requeued message' do
          # wait for failing message
          sleep 1

          message = redis.get(queue_name)

          refute_nil(message)
        end

        it 'it has been routed to retry exchange once' do
          # wait for failing message
          sleep 1

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death = message_headers['x-death'].detect do |x|
            x['queue'] == queue_name
          end

          assert_equal(consumer_x_death['count'], 1)
          assert_equal(consumer_x_death['reason'], 'rejected')
          assert_equal(consumer_x_death['exchange'], exchange_name)
        end

        it 'it has been routed to requeue exchange once' do
          # wait for failing message
          sleep 1

          message = JSON.load(redis.get(queue_name))
          message_headers = message['message_properties']['headers']
          consumer_x_death = message_headers['x-death'].detect do |x|
            x['queue'] == retry_queue_name
          end

          assert_equal(consumer_x_death['count'], 1)
          assert_equal(consumer_x_death['reason'], 'expired')
          assert_equal(consumer_x_death['exchange'], retry_exchange)
        end
      end
    end
  end

  def cleanup_redis(client)
    keys = client.keys('integration_*')
    integration_log 'cleaning up redis'
    client.del(keys) unless keys.empty?
  end

  def prepare_sneakers(opts = {})
    Sneakers.clear!
    Sneakers.configure(opts)
    Sneakers.logger.level = Logger::ERROR
  end

  def get_message_from_queue(queue_name)
    connection = Bunny.new
    connection.start
    channel = connection.create_channel
    message = channel.basic_get(queue_name)
    channel.acknowledge(message.first.delivery_tag) if message.first

    message
  end

  def cleanup_rabbitmq(client)
    # clean up all integration queues; admin interface must be installed
    # in integration env
    integration_log 'cleaning up RabbitMQ'
    queues = client.list_queues
    queues.each do |q|
      name = q.name
      if name.start_with? 'integration_'
        client.delete_queue('/', name)
        integration_log "delete queue #{name}."
      end
    end

    exchanges = client.list_exchanges
    exchanges.each do |exchange|
      name = exchange.name
      if name.start_with? 'integration_'
        client.delete_exchange('/', name)
        integration_log "delete exchange #{name}."
      end
    end
  end

  def start_worker(w)
    integration_log "starting workers."
    r = Sneakers::Runner.new([w])
    pid = fork {
       r.run
    }

    integration_log "waiting for workers to stabilize (5s)."
    sleep 5

    pid
  end

  def integration_log(msg)
    puts msg if ENV['INTEGRATION_LOG']
  end
end
