require 'spec_helper'

describe Sneakers::Configuration do

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

  def with_env(key, value)
    old_value = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old_value
  end
end