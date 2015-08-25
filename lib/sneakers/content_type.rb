module Sneakers
  class ContentType
    def self.register(content_type: nil, serializer: nil, deserializer: nil)
      # This can be removed when support is dropped for ruby 2.0 and replaced
      # by a keyword arg with no default value
      fail ArgumentError, 'missing keyword: content_type' if content_type.nil?
      fail ArgumentError, 'missing keyword: serializer' if serializer.nil?
      fail ArgumentError, 'missing keyword: deserializer' if deserializer.nil?

      fail ArgumentError, "#{content_type} serializer must be a proc" unless serializer.is_a? Proc
      fail ArgumentError, "#{content_type} deserializer must be a proc" unless deserializer.is_a? Proc

      fail ArgumentError, "#{content_type} serializer must accept one argument, the payload" unless serializer.arity == 1
      fail ArgumentError, "#{content_type} deserializer must accept one argument, the payload" unless deserializer.arity == 1
      @_types[content_type] = new(serializer, deserializer)
    end

    def self.serialize(payload, content_type)
      return payload unless content_type
      @_types[content_type].serializer.(payload)
    end

    def self.deserialize(payload, content_type)
      return payload unless content_type
      @_types[content_type].deserializer.(payload)
    end

    def self.reset!
      @_types = Hash.new(
        new(passthrough, passthrough)
      )
    end

    def self.passthrough
      ->(payload) { payload }
    end

    def initialize(serializer, deserializer)
      @serializer = serializer
      @deserializer = deserializer
    end

    attr_reader :serializer, :deserializer

    reset!
  end
end
