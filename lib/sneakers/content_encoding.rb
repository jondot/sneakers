module Sneakers
  class ContentEncoding
    def self.register(content_encoding: nil, encoder: nil, decoder: nil)
      # This can be removed when support is dropped for ruby 2.0 and replaced
      # by a keyword arg with no default value
      fail ArgumentError, 'missing keyword: content_encoding' if content_encoding.nil?
      fail ArgumentError, 'missing keyword: encoder' if encoder.nil?
      fail ArgumentError, 'missing keyword: decoder' if decoder.nil?

      fail ArgumentError, "#{content_encoding} encoder must be a proc" unless encoder.is_a? Proc
      fail ArgumentError, "#{content_encoding} decoder must be a proc" unless decoder.is_a? Proc

      fail ArgumentError, "#{content_encoding} encoder must accept one argument, the payload" unless encoder.arity == 1
      fail ArgumentError, "#{content_encoding} decoder must accept one argument, the payload" unless decoder.arity == 1
      @_encodings[content_encoding] = new(encoder, decoder)
    end

    def self.encode(payload, content_encoding)
      return payload unless content_encoding
      @_encodings[content_encoding].encoder.(payload)
    end

    def self.decode(payload, content_encoding)
      return payload unless content_encoding
      @_encodings[content_encoding].decoder.(payload)
    end

    def self.reset!
      @_encodings = Hash.new(
        new(passthrough, passthrough)
      )
    end

    def self.passthrough
      ->(payload) { payload }
    end

    def initialize(encoder, decoder)
      @encoder = encoder
      @decoder = decoder
    end

    attr_reader :encoder, :decoder

    reset!
  end
end
