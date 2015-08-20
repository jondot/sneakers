module Sneakers
  class ContentType
    def self.register(content_type: nil, serializer: nil, deserializer: nil)
      @_types[content_type] = new(serializer, deserializer)
    end

    def self.[](content_type)
      @_types[content_type]
    end

    def self.reset!
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
