module Sneakers
  class ContentType
    def self.register(content_type: nil, serializer: nil, deserializer: nil)
      @_active = true
      @_types[content_type] = new(serializer, deserializer)
    end

    def self.serialize(payload, content_type)
      return payload unless @_active
      @_types[content_type].serialize(payload)
    end

    def self.deserialize(payload, content_type)
      return payload unless @_active
      @_types[content_type].deserialize(payload)
    end

    def self.reset!
      @_active = false
      @_types = Hash.new(
        new(->(payload) { payload }, ->(payload) { payload })
      )
    end

    def initialize(serializer, deserializer)
      @serializer = serializer
      @deserializer = deserializer
    end

    def serialize(payload)
      @serializer.(payload)
    end

    def deserialize(payload)
      @deserializer.(payload)
    end

    reset!
  end
end
