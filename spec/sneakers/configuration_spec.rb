require 'spec_helper'

describe Sneakers::Configuration do

  describe 'with a connection' do
    let(:connection) { Object.new }

    it 'does not use vhost option if it is specified' do
      url = 'amqp://foo:bar@localhost:5672/foobarvhost'
      with_env('RABBITMQ_URL', url) do
        config = Sneakers::Configuration.new
        config.merge!({ :vhost => 'test_host', :connection => connection })
        config.has_key?(:vhost).must_equal false
      end
    end

    it 'does not amqp option if it is specified' do
      url = 'amqp://foo:bar@localhost:5672'
      config = Sneakers::Configuration.new
      config.merge!({ :amqp => url, :connection => connection })
      config.has_key?(:vhost).must_equal false
    end
  end

  describe 'without a connection' do
    it 'should assign a default value for :amqp' do
      with_env('RABBITMQ_URL', nil) do
        config = Sneakers::Configuration.new
        config[:amqp].must_equal 'amqp://guest:guest@localhost:5672'
      end
    end

    it 'should assign a default value for :vhost' do
      with_env('RABBITMQ_URL', nil) do
        config = Sneakers::Configuration.new
        config[:vhost].must_equal '/'
      end
    end

    it 'should read the value for amqp from RABBITMQ_URL' do
      url = 'amqp://foo:bar@localhost:5672'
      with_env('RABBITMQ_URL', url) do
        config = Sneakers::Configuration.new
        config[:amqp].must_equal url
      end
    end

    it 'should read the value for vhost from RABBITMQ_URL' do
      url = 'amqp://foo:bar@localhost:5672/foobarvhost'
      with_env('RABBITMQ_URL', url) do
        config = Sneakers::Configuration.new
        config[:vhost].must_equal 'foobarvhost'
      end
    end

    it 'should parse vhost from amqp option' do
      env_url = 'amqp://foo:bar@localhost:5672/foobarvhost'
      with_env('RABBITMQ_URL', env_url) do
        url = 'amqp://foo:bar@localhost:5672/testvhost'
        config = Sneakers::Configuration.new
        config.merge!({ :amqp => url })
        config[:vhost].must_equal 'testvhost'
      end
    end

    it 'should not parse vhost from amqp option if vhost is specified explicitly' do
      url = 'amqp://foo:bar@localhost:5672/foobarvhost'
      config = Sneakers::Configuration.new
      config.merge!({ :amqp => url, :vhost => 'test_host' })
      config[:vhost].must_equal 'test_host'
    end

    it 'should use vhost option if it is specified' do
      url = 'amqp://foo:bar@localhost:5672/foobarvhost'
      with_env('RABBITMQ_URL', url) do
        config = Sneakers::Configuration.new
        config.merge!({ :vhost => 'test_host' })
        config[:vhost].must_equal 'test_host'
      end
    end

    it 'should use default vhost if vhost is not specified in amqp option' do
      url = 'amqp://foo:bar@localhost:5672'
      config = Sneakers::Configuration.new
      config.merge!({ :amqp => url })
      config[:vhost].must_equal '/'
    end
  end

  def with_env(key, value)
    old_value = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old_value
  end
end
