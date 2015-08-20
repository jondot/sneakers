module Sneakers
  class ContentType
    def self.register(content_type: nil, serializer: nil, deserializer: nil)
      @_types[content_type] = new(serializer, deserializer)
    end

    def self.serialize(payload, content_type)
      @_types[content_type].serializer.(payload)
    end

    def self.deserialize(payload, content_type)
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
