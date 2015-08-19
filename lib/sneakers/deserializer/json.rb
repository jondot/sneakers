module Sneakers
  module Deserializer
    module JSON
      def self.included(receiver)
        _do_work = receiver.instance_method(:do_work)
        receiver.send(:define_method, :do_work) do |delivery_info, metadata, msg, handler|
          msg = ::JSON.parse(msg) if metadata[:content_type] == 'application/json'
          _do_work.bind(self).(delivery_info, metadata, msg,handler)
        end
      end
    end
  end
end
