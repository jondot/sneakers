require 'spec_helper'
require 'sneakers/content_type'
require 'base64'

describe Sneakers::ContentType do
  after do
    Sneakers::ContentType.reset!
  end

  describe '.deserialize' do
    it 'uses the given deserializer' do
      Sneakers::ContentType.register(
        content_type: 'application/json',
        serializer: ->(_) {},
        deserializer: ->(payload) { JSON.parse(payload) },
      )

      Sneakers::ContentType.deserialize('{"foo":"bar"}', 'application/json').must_equal('foo' => 'bar')
    end
  end

  describe '.serialize' do
     it 'uses the given serializer' do
      Sneakers::ContentType.register(
        content_type: 'application/json',
        serializer: ->(payload) { JSON.dump(payload) },
        deserializer: ->(_) {},
      )

      Sneakers::ContentType.serialize({ 'foo' => 'bar' }, 'application/json').must_equal('{"foo":"bar"}')
    end

    it 'passes the payload through by default' do
      payload = "just some text"
      Sneakers::ContentType.serialize(payload, 'unknown/type').must_equal(payload)
      Sneakers::ContentType.deserialize(payload, 'unknown/type').must_equal(payload)
      Sneakers::ContentType.serialize(payload, nil).must_equal(payload)
      Sneakers::ContentType.deserialize(payload, nil).must_equal(payload)
    end

    it 'passes the payload through if type not found' do
      Sneakers::ContentType.register(content_type: 'found/type', serializer: ->(_) {}, deserializer: ->(_) {})
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

    it 'requires a content type' do
      proc { Sneakers::ContentType.register(serializer: -> { }, deserializer: -> { }) }.must_raise ArgumentError
    end

    it 'expects serializer and deserializer to be present' do
      proc { Sneakers::ContentType.register(content_type: 'foo', deserializer: -> { }) }.must_raise ArgumentError
      proc { Sneakers::ContentType.register(content_type: 'foo', serializer: -> { }) }.must_raise ArgumentError
    end

    it 'expects serializer and deserializer to be a proc' do
      proc { Sneakers::ContentType.register(content_type: 'foo', serializer: 'not a proc', deserializer: ->(_) { }) }.must_raise ArgumentError
      proc { Sneakers::ContentType.register(content_type: 'foo', serializer: ->(_) {}, deserializer: 'not a proc' ) }.must_raise ArgumentError
    end

    it 'expects serializer and deserializer to have the correct arity' do
      proc { Sneakers::ContentType.register(content_type: 'foo', serializer: ->(_,_) {}, deserializer: ->(_) {}) }.must_raise ArgumentError
      proc { Sneakers::ContentType.register(content_type: 'foo', serializer: ->(_) {}, deserializer: ->() {} ) }.must_raise ArgumentError
    end
  end
end
