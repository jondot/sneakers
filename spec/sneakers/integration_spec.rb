require 'spec_helper'
require 'sneakers'
require 'sneakers/runner'
require 'fixtures/integration_worker'

require "rabbitmq/http/client"


describe "integration" do
  describe 'first' do
    before :each do
      skip unless ENV['INTEGRATION']
      prepare
    end

    def integration_log(msg)
      puts msg if ENV['INTEGRATION_LOG']
    end

    def prepare
      # clean up all integration queues; admin interface must be installed
      # in integration env
      rmq_addr = compose_or_localhost("rabbitmq")
      puts "RABBITMQ is at #{rmq_addr}"
      begin
        admin = RabbitMQ::HTTP::Client.new("http://#{rmq_addr}:15672/", username: "guest", password: "guest")
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
      Sneakers.configure(:amqp => "amqp://guest:guest@#{rmq_addr}:5672")
      Sneakers.logger.level = Logger::ERROR

      # configure integration worker on a random generated queue
      random_queue = "integration_#{rand(10**36).to_s(36)}"

      redis_addr = compose_or_localhost("redis")
      @redis = Redis.new(:host => redis_addr)
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

    def any_consumers
      rmq_addr = compose_or_localhost("rabbitmq")
      result = false
      begin
        admin = RabbitMQ::HTTP::Client.new("http://#{rmq_addr}:15672/", username: "guest", password: "guest")
        qs = admin.list_queues
        qs.each do |q|
          if q.name.start_with? 'integration_'
            puts "We see #{q.consumers} consumers on #{q.name}"
            return true if q.consumers > 0
          end
        end
        return false
      rescue
        puts "Rabbitmq admin seems to not exist? you better be running this on Travis or Docker. proceeding.\n#{$!}"
      end
    end

    it 'should be possible to terminate when queue is full' do
      job_count = 40000

      pid = start_worker(IntegrationWorker)
      Process.kill("TERM", pid)

      integration_log "publishing #{job_count} messages..."
      p = Sneakers::Publisher.new
      job_count.times do |i|
        p.publish("m #{i}", to_queue: IntegrationWorker.queue_name)
      end

      pid = start_worker(IntegrationWorker)
      any_consumers.must_equal true
      integration_log "Killing #{pid} now!"
      Process.kill("TERM", pid)
      sleep(2)
      any_consumers.must_equal false
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
end


