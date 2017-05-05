require 'spec_helper'
require 'sneakers'
require 'sneakers/handlers/routing_maxretry'

describe Sneakers::Handlers::RoutingMaxretry do
  let(:channel) { Object.new }
  let(:queue) { Object.new }
  let(:worker_opts) { {} }
  let(:opts) { {} }
  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log) }

  subject do
    Sneakers::Handlers::RoutingMaxretry.new(channel, queue, worker_opts)
  end

  before do
    stub(Sneakers).logger { logger }
  end

  describe '#initialize' do
    let(:log_prefix) { 'BOOM!' }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        mock(handler).log_prefix { log_prefix }
        mock(handler).init_opts(worker_opts) { opts }
        mock(handler).create_queues_and_bindings
      end
    end

    it 'assigns channel variable' do
      assert_equal(channel, subject.channel)
    end

    it 'assigns queue variable' do
      assert_equal(queue, subject.queue)
    end

    it 'assigns opts variable' do
      assert_equal(opts, subject.opts)
    end

    it 'writes log' do
      subject

      log.rewind

      assert_match('BOOM! creating handler, opts={}', log.first)
    end
  end

  describe '#acknowledge' do
    let(:channel) { Minitest::Mock.new }
    let(:delivery_tag) { Object.new }
    let(:delivery_info) { Minitest::Mock.new }
    let(:message_properties) { Object.new }
    let(:payload) { Object.new }

    before do
      stub(delivery_info).delivery_tag { delivery_tag }
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'acknowledges message' do
      channel.expect(:acknowledge, true, [delivery_tag])

      subject.acknowledge(delivery_info, message_properties, payload)

      channel.verify
    end
  end

  describe '#reject' do
    let(:channel) { Minitest::Mock.new }
    let(:delivery_tag) { Object.new }
    let(:delivery_info) { Minitest::Mock.new }

    let(:message_properties) { Object.new }
    let(:payload) { 'payload' }

    let(:reject) do
      subject.reject(delivery_info, message_properties, payload, requeue)
    end

    before do
      stub(delivery_info).delivery_tag { delivery_tag }
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    describe 'when reject requeueing is enabled' do
      let(:requeue) { true }

      it 'rejects message' do
        channel.expect(:reject, true, [delivery_tag, requeue])

        reject

        channel.verify
      end
    end

    describe 'when reject requeueing is disabled' do
      let(:requeue) { false }
      let(:handle_retry) { Minitest::Mock.new }

      before do
        any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
          stub(handler).init_opts(worker_opts) { opts }
          stub(handler).create_queues_and_bindings
        end
      end

      it 'calls "#handle_retry"' do
        handle_retry.expect(
          :call,
          true,
          [delivery_info, message_properties, payload, :reject]
        )

        subject.stub(:handle_retry, handle_retry) do
          reject
        end

        handle_retry.verify
      end
    end
  end

  describe '#error' do
    let(:delivery_info) { Object.new }
    let(:message_properties) { Object.new }
    let(:payload) { 'payload' }
    let(:handle_retry) { Minitest::Mock.new }
    let(:error) { Object.new }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'calls "#handle_retry"' do
      handle_retry.expect(
        :call,
        true,
        [delivery_info, message_properties, payload, error]
      )

      subject.stub(:handle_retry, handle_retry) do
        subject.error(delivery_info, message_properties, payload, error)
      end

      handle_retry.verify
    end
  end

  describe '#timeout' do
    let(:delivery_info) { Object.new }
    let(:message_properties) { Object.new }
    let(:payload) { 'payload' }
    let(:handle_retry) { Minitest::Mock.new }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'calls "#handle_retry"' do
      handle_retry.expect(
        :call,
        true,
        [delivery_info, message_properties, payload, :timeout]
      )

      subject.stub(:handle_retry, handle_retry) do
        subject.timeout(delivery_info, message_properties, payload)
      end

      handle_retry.verify
    end
  end

  describe '#init_opts' do
    let(:queue) { Minitest::Mock.new }

    before do
      stub(queue).name { 'foo' }
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).create_queues_and_bindings
      end
    end

    describe 'when given options are empty hash' do
      let(:worker_opts) { {} }
      it 'builds the options hash with defaults' do
        expected = {
          error_queue_name:    'foo.error',
          error_routing_key:   'queue.foo.error',
          requeue_routing_key: 'queue.foo.requeue',
          retry_max_times:     5,
          retry_queue_name:    'foo.retry',
          retry_routing_key:   'queue.foo.retry',
          retry_timeout:       6000,
          worker_queue_name:   'foo'
        }

        assert_equal(expected, subject.send(:init_opts, worker_opts))
      end
    end

    describe 'when given options are not empty' do
      let(:worker_opts) do
        {
          error_queue_name:    'bar.error',
          error_routing_key:   'queue.bar.error',
          requeue_routing_key: 'queue.bar.retry',
          retry_queue_name:    'bar.delayed',
          retry_routing_key:   'queue.bar.delayed',
          worker_queue_name:   'bar'
        }
      end

      it 'builds the options hash with defaults' do
        expected = {
          error_queue_name:    'bar.error',
          error_routing_key:   'queue.bar.error',
          requeue_routing_key: 'queue.bar.retry',
          retry_max_times:     5,
          retry_queue_name:    'bar.delayed',
          retry_routing_key:   'queue.bar.delayed',
          retry_timeout:       6000,
          worker_queue_name:   'bar'
        }
        assert_equal(expected, subject.send(:init_opts, worker_opts))
      end
    end
  end

  describe '#create_queues_and_bindings' do
    let(:exchange_name) { 'name' }
    let(:routing_key)   { 'routing_key' }
    let(:opts) { { requeue_routing_key: routing_key, exchange: exchange_name } }
    let(:create_queues_and_bindings) do
      subject.send(:create_queues_and_bindings)
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_retry_queue_and_binding
        stub(handler).create_error_queue_and_binding
      end
    end

    it 'calls "#create_retry_queue_and_binding"' do
      stub(queue).bind(exchange_name, routing_key: routing_key)

      create_retry_queue_and_binding = Minitest::Mock.new
      create_retry_queue_and_binding.expect(:call, true)

      subject.stub(
        :create_retry_queue_and_binding,
        create_retry_queue_and_binding
      ) { create_queues_and_bindings }

      create_retry_queue_and_binding.verify
    end

    it 'calls "#create_error_queue_and_binding"' do
      stub(queue).bind(exchange_name, routing_key: routing_key)

      create_error_queue_and_binding = Minitest::Mock.new
      create_error_queue_and_binding.expect(:call, true)

      subject.stub(
        :create_error_queue_and_binding,
        create_error_queue_and_binding
      ) { create_queues_and_bindings }

      create_error_queue_and_binding.verify
    end

    it 'creates binding' do
      stub(queue).bind

      mock_queue = Minitest::Mock.new
      mock_queue.expect(:bind, nil, [exchange_name, routing_key: routing_key])

      stub(subject).queue { mock_queue }

      create_queues_and_bindings

      mock_queue.verify
    end
  end

  describe '#create_error_queue_and_binding' do
    let(:queue_name) { 'queue_name' }
    let(:routing_key) { 'routing_key' }
    let(:opts) do
      { error_queue_name: queue_name, error_routing_key: routing_key }
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'calls "#create_queue_and_binding"' do
      create_queue_and_binding = Minitest::Mock.new
      create_queue_and_binding.expect(:call, nil, [queue_name, routing_key])

      subject.stub(:create_queue_and_binding, create_queue_and_binding) do
        subject.send(:create_error_queue_and_binding)
      end

      create_queue_and_binding.verify
    end
  end

  describe '#create_retry_queue_and_binding' do
    let(:queue_name) { 'queue_name' }
    let(:routing_key) { 'routing_key' }
    let(:retry_queue_arguments) { Object.new }
    let(:opts) do
      { retry_queue_name: queue_name, retry_routing_key: routing_key }
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      stub(subject).retry_queue_arguments { retry_queue_arguments }
    end

    it 'calls "#create_queue_and_binding"' do
      create_queue_and_binding = Minitest::Mock.new
      create_queue_and_binding.expect(
        :call,
        nil,
        [queue_name, routing_key, arguments: retry_queue_arguments]
      )

      subject.stub(:create_queue_and_binding, create_queue_and_binding) do
        subject.send(:create_retry_queue_and_binding)
      end

      create_queue_and_binding.verify
    end
  end

  describe '#retry_queue_arguments' do
    let(:exchange_name) { 'name' }
    let(:retry_timeout) { 42 }
    let(:requeue_routing_key) { 'foo' }
    let(:opts) do
      {
        exchange: exchange_name,
        retry_timeout: retry_timeout,
        requeue_routing_key: requeue_routing_key
      }
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'returns arguments hash' do
      expected = {
        'x-dead-letter-exchange'    => exchange_name,
        'x-message-ttl'             => retry_timeout,
        'x-dead-letter-routing-key' => requeue_routing_key
      }

      assert_equal(expected, subject.send(:retry_queue_arguments))
    end
  end

  describe '#create_queue_and_binding' do
    let(:queue_name) { 'queue_name' }
    let(:routing_key) { 'routing_key' }

    let(:log_prefix) { 'BAAAM!!!' }
    let(:created_queue) { Object.new }
    let(:durable) { true }
    let(:exchange_name) { 'name' }
    let(:opts) { { exchange: exchange_name } }

    let(:create_queue_and_binding) do
      subject.send(:create_queue_and_binding, queue_name, routing_key)
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
      stub(subject).queue_durable? { durable }
    end

    it 'writes log' do
      stub(channel).queue { created_queue }
      stub(subject).channel { channel }
      stub(created_queue).bind
      stub(subject).log_prefix { log_prefix }

      create_queue_and_binding

      log.rewind

      assert_match(
        'BAAAM!!! creating queue=queue_name, arguments={}',
        log.readlines.last
      )
    end

    it 'creates queue' do
      stub(created_queue).bind

      mock_channel = Minitest::Mock.new
      mock_channel.expect(:queue, created_queue, [queue_name, durable: durable])

      stub(subject).channel { mock_channel }

      create_queue_and_binding

      mock_channel.verify
    end

    it 'creates binding' do
      mock_queue = Minitest::Mock.new
      mock_queue.expect(:bind, nil, [exchange_name, routing_key: routing_key])

      stub(channel).queue { mock_queue }
      stub(subject).channel { channel }

      create_queue_and_binding

      mock_queue.verify
    end
  end

  describe '#handle_retry' do
    let(:delivery_info) { Object.new }
    let(:headers) { Object.new }
    let(:message_properties) { Object.new }
    let(:payload) { 'payload' }
    let(:reason) { Object.new }
    let(:failure_count) { 42 }
    let(:retry_max_times) { 23 }
    let(:opts) { { retry_max_times: retry_max_times } }

    let(:handle_retry) do
      subject.send(
        :handle_retry,
        delivery_info,
        message_properties,
        payload,
        reason
      )
    end

    before do
      stub(message_properties).headers { headers }

      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings

        stub(handler).failure_count { failure_count }
        stub(handler).reject_to_retry
        stub(handler).publish_to_error_queue
      end
    end

    it 'calls "#failure_count"' do
      mock_failure_count = Minitest::Mock.new
      mock_failure_count.expect(:call, failure_count, [headers])

      subject.stub(:failure_count, mock_failure_count) do
        handle_retry
      end

      mock_failure_count.verify
    end

    describe 'when max retries not reached' do
      let(:failure_count) { 22 }

      it 'calls "#reject_to_retry"' do
        mock_reject_to_retry = Minitest::Mock.new
        mock_reject_to_retry.expect(
          :call,
          nil,
          [delivery_info, message_properties, failure_count + 1]
        )

        subject.stub(:reject_to_retry, mock_reject_to_retry) do
          handle_retry
        end

        mock_reject_to_retry.verify
      end
    end

    describe 'when max retries reached' do
      let(:failure_count) { 23 }

      it 'calls "#publish_to_error_queue"' do
        mock_publish_to_error_queue = Minitest::Mock.new
        mock_publish_to_error_queue.expect(
          :call,
          nil,
          [
            delivery_info,
            message_properties,
            payload,
            reason,
            failure_count + 1
          ]
        )

        subject.stub(:publish_to_error_queue, mock_publish_to_error_queue) do
          handle_retry
        end

        mock_publish_to_error_queue.verify
      end
    end
  end

  describe '#publish_to_error_queue' do
    let(:exchange_name) { 'name' }
    let(:error_routing_key) { 'routing_key' }
    let(:opts) do
      { error_routing_key: error_routing_key, exchange: exchange_name }
    end
    let(:delivery_tag) { Object.new }
    let(:delivery_info) { Object.new }
    let(:payload) { 'payload' }
    let(:num_attempts) { 5 }
    let(:reason) { :reason }
    let(:log_prefix) { 'BOOM!!!' }
    let(:error_payload) { Object.new }
    let(:message_properties) { Object.new }

    let(:publish_to_error_queue) do
      subject.send(
        :publish_to_error_queue,
        delivery_info,
        message_properties,
        message,
        reason,
        num_attempts
      )
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      stub(delivery_info).delivery_tag { delivery_tag }
      stub(subject).error_payload { error_payload }
    end

    it 'writes log' do
      stub(subject).log_prefix { log_prefix }
      stub(channel).basic_publish
      stub(channel).acknowledge

      publish_to_error_queue

      log.rewind

      assert_match(
        'BOOM!!! '\
        "message=failing, retry_count=#{num_attempts}, reason=#{reason}",
        log.readlines.last
      )
    end

    it 'calls channel.basic_publish' do
      mock_channel = Minitest::Mock.new
      mock_channel.expect(
        :basic_publish,
        nil,
        [error_payload, exchange_name, error_routing_key, content_type: 'application/json']
      )

      stub(mock_channel).acknowledge
      stub(subject).channel { mock_channel }

      publish_to_error_queue

      mock_channel.verify
    end

    it 'calls channel.acknowledge' do
      mock_channel = Minitest::Mock.new
      mock_channel.expect(:acknowledge, nil, [delivery_tag])

      stub(mock_channel).basic_publish
      stub(subject).channel { mock_channel }

      publish_to_error_queue

      mock_channel.verify
    end
  end

  describe '#reject_to_retry' do
    let(:headers) { Object.new }
    let(:message_properties) { Object.new }
    let(:delivery_tag) { Object.new }
    let(:delivery_info) { Object.new }
    let(:num_attempts) { 5 }
    let(:log_prefix) { 'FOO!!!' }

    let(:reject_to_retry) do
      subject.send(
        :reject_to_retry,
        delivery_info,
        message_properties,
        num_attempts
      )
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      stub(message_properties).headers { headers }
      stub(delivery_info).delivery_tag { delivery_tag }
    end

    it 'writes log' do
      stub(subject).log_prefix { log_prefix }
      stub(channel).reject

      reject_to_retry

      log.rewind

      assert_match(
        "FOO!!! msg=retrying, count=#{num_attempts}, " \
        "headers=#{message_properties.headers}",
        log.readlines.last
      )
    end

    it 'calls channel.acknowledge' do
      mock_channel = Minitest::Mock.new
      mock_channel.expect(:reject, nil, [delivery_tag])

      stub(subject).channel { mock_channel }

      reject_to_retry

      mock_channel.verify
    end
  end

  describe '#error_payload' do
    let(:reason) { :reason }
    let(:num_attempts) { 5 }
    let(:payload) { 'ABCD' }
    let(:timestamp) { '2016-02-11T17:44:55+01:00' }
    let(:delivery_info) { Object.new }
    let(:message_properties) { Object.new }

    let(:error_payload) do
      JSON.parse(
        subject.send(
          :error_payload,
          delivery_info,
          message_properties,
          payload,
          reason,
          num_attempts
        )
      )
    end

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      any_instance_of(Time) do |time|
        stub(time).iso8601 { timestamp }
      end

      stub(delivery_info).to_hash { {} }
      stub(message_properties).to_hash { {} }
    end

    it 'creates JSON hash with _error key' do
      assert_equal(error_payload.keys, ['_error'])
    end

    it 'created the error_payload json including the reason' do
      expected = { 'reason' => reason.to_s }

      assert_equal(
        error_payload['_error'].merge(expected),
        error_payload['_error']
      )
    end

    it 'created the error_payload json including the number of attempts' do
      expected = { 'num_attempts' => num_attempts }

      assert_equal(
        error_payload['_error'].merge(expected),
        error_payload['_error']
      )
    end

    it 'created the error_payload json including the failed_at timestamp' do
      expected = { 'failed_at' => timestamp }

      assert_equal(
        error_payload['_error'].merge(expected),
        error_payload['_error']
      )
    end

    it 'created the error_payload json including the payload' do
      expected = { 'payload' => payload }

      assert_equal(
        error_payload['_error'].merge(expected),
        error_payload['_error']
      )
    end

    it 'created the error_payload json including the ' \
       '"#exception_payload" result' do
      stub(subject).exception_payload(reason) { { foo: 'bar' } }

      expected = { 'foo' => 'bar' }
      assert_equal(
        error_payload['_error'].merge(expected),
        error_payload['_error']
      )
    end
  end

  describe '#exception_payload' do
    let(:exception_payload) { subject.send(:exception_payload, reason) }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    describe 'when reason is not an exception' do
      let(:reason) { 'reason' }

      it 'returns empty hash' do
        assert_equal({}, exception_payload)
      end
    end

    describe 'when reason is an exception' do
      let(:reason) { RuntimeError.new('Foo') }

      it 'returns hash including error class and message' do
        expected = {
          error_class:   'RuntimeError',
          error_message: 'Foo'
        }
        assert_equal(exception_payload.merge(expected), exception_payload)
      end

      it 'returns hash including "#exception_backtrace" result' do
        stub(subject).exception_backtrace(reason) { { foo: 'bar' } }

        expected = { foo: 'bar' }

        assert_equal(exception_payload.merge(expected), exception_payload)
      end
    end
  end

  describe '#exception_backtrace' do
    let(:reason) { Object.new }

    let(:exception_backtrace) { subject.send(:exception_backtrace, reason) }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      stub(reason).backtrace { backtrace }
    end

    describe 'when backtrace is nil' do
      let(:backtrace) { nil }

      it 'returns empty hash' do
        assert_equal({}, exception_backtrace)
      end
    end

    describe 'when backtrace exists' do
      let(:backtrace) { (1..11).to_a.map { |a| "line#{a}" } }

      it 'returns hash including first 10 lines of backtrace' do
        expected = {
          backtrace: 'line1, line2, line3, line4, line5, line6, line7, ' \
                     'line8, line9, line10'
        }

        assert_equal(exception_backtrace.merge(expected), exception_backtrace)
      end
    end
  end

  describe '#failure_count' do
    let(:headers) { Object.new }
    let(:x_death_array) { [] }

    let(:failure_count) { subject.send(:failure_count, headers) }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end

      stub(subject).x_death_array(headers) { x_death_array }
    end

    it 'calls "#x_death_array"' do
      mock_x_death_array = Minitest::Mock.new
      mock_x_death_array.expect(:call, x_death_array, [headers])

      subject.stub(:x_death_array, mock_x_death_array) do
        failure_count
      end

      mock_x_death_array.verify
    end

    describe 'when x_death array is empty' do
      it 'returns 0' do
        assert_equal(0, failure_count)
      end
    end

    describe 'when first x_death array element has no count key' do
      let(:x_death_array) { [{ one: 1 }, { two: 2 }, { three: 3 }] }

      it 'returns x_death array length' do
        assert_equal(3, failure_count)
      end
    end

    describe 'when first x_death array element has a count key' do
      let(:x_death_array) { [{ 'count' => '23' }, { 'count' => '2' }] }

      it 'returns first x_death array elements count key' do
        assert_equal(23, failure_count)
      end
    end
  end

  describe '#x_death_array' do
    let(:x_death_array) { subject.send(:x_death_array, headers) }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    describe 'when headers is nil' do
      let(:headers) { nil }

      it 'returns empty array' do
        assert_equal([], x_death_array)
      end
    end

    describe 'when no x-death header exists' do
      let(:headers) { { foo: 'bar' } }

      it 'returns empty array' do
        assert_equal([], x_death_array)
      end
    end

    describe 'when x-death header exists' do
      let(:opts) { { worker_queue_name: 'foo' } }
      let(:headers) do
        {
          'x-death' => [
            { 'queue' => 'foo', 'xyz' => 1 },
            { 'queue' => 'bar', 'xyz' => 2 },
            { 'queue' => 'foo', 'xyz' => 3 },
            { 'queue' => 'bar', 'xyz' => 4 },
            { 'queue' => 'baz', 'xyz' => 5 }
          ]
        }
      end

      it 'returns x_death header for worker queue' do
        expected = [
          { 'queue' => 'foo', 'xyz' => 1 },
          { 'queue' => 'foo', 'xyz' => 3 }
        ]

        assert_equal(expected, x_death_array)
      end
    end
  end

  describe '#log_prefix' do
    let(:opts) { { worker_queue_name: 'bamm' } }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    it 'returns the log prefix' do
      assert_equal(
        'Sneakers::Handlers::RoutingMaxretry handler [queue=bamm]',
        subject.send(:log_prefix)
      )
    end
  end

  describe '#queue_durable?' do
    let(:queue_durable?) { subject.send(:queue_durable?) }

    before do
      any_instance_of(Sneakers::Handlers::RoutingMaxretry) do |handler|
        stub(handler).init_opts(worker_opts) { opts }
        stub(handler).create_queues_and_bindings
      end
    end

    describe 'when no queue options exists' do
      let(:opts) { {} }

      it 'returns false' do
        refute(queue_durable?)
      end
    end

    describe 'when queue options exists' do
      describe 'when durable is not set' do
        let(:opts) { { queue_options: {} } }

        it 'returns false' do
          refute(queue_durable?)
        end
      end

      describe 'when durable is set' do
        let(:durable) { true }
        let(:opts) { { queue_options: { durable: durable } } }

        it 'returns durable value' do
          assert_equal(durable, queue_durable?)
        end
      end
    end
  end
end
