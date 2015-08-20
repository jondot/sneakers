require 'spec_helper'
require 'sneakers/content_type'
require 'base64'

describe Sneakers::ContentType do
  after do
    Sneakers::ContentType.reset!
  end

  describe '#serialize' do
    it 'uses the given serializer' do
      json = Sneakers::ContentType.new(
        ->(payload) { JSON.dump(payload) },
        nil,
      )

      json.serialize('foo' => 'bar').must_equal('{"foo":"bar"}')
    end
  end

  describe '#deserialize' do
    it 'uses the given deserializer' do
      json = Sneakers::ContentType.new(
        nil,
        ->(payload) { JSON.parse(payload) },
      )

      json.deserialize('{"foo":"bar"}').must_equal('foo' => 'bar')
    end
  end

  describe '.serialize' do
    it 'returns a pass through by default' do
      payload = "just some text"
      Sneakers::ContentType.serialize(payload, 'unknown/type').must_equal(payload)
      Sneakers::ContentType.deserialize(payload, 'unknown/type').must_equal(payload)
    end

    it 'returns a pass through if not found type' do
      Sneakers::ContentType.register(content_type: 'found/type')
      payload = "just some text"

      Sneakers::ContentType.serialize(payload, 'unknown/type').must_equal(payload)
      Sneakers::ContentType.deserialize(payload, 'unknown/type').must_equal(payload)
    end
  end

  describe '.register' do
    it 'provides a mechnism to register a given type' do
      Sneakers::ContentType.register(
        content_type: 'text/base64',
        serializer: ->(payload) { Base64.encode64(payload) },
        deserializer: ->(payload) { Base64.decode64(payload) },
      )

      ct = Sneakers::ContentType
      ct.deserialize(ct.serialize('hello world', 'text/base64'), 'text/base64').must_equal('hello world')
    end
  end
end
