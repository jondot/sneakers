module Sneakers
  module Middleware
    class Config
      def self.use(klass, args)
        middlewares << { class: klass, args: args }
      end

      def self.delete(klass)
        middlewares.reject! { |el| el[:class] == klass }
      end

      def self.to_a
        middlewares
      end

      def self.middlewares
        @middlewares ||= []
      end

      private_class_method :middlewares
    end
  end
end
