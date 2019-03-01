$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'

class MiddlewareWorker
  include Sneakers::Worker

  from_queue 'middleware-demo',
    ack: false

  def work(message)
    puts "******** MiddlewareWorker -> #{message}"
  end
end

class DemoMiddleware
  def initialize(app, *args)
    @app = app
    @args = args
  end

  def call(deserialized_msg, delivery_info, metadata, handler)
    puts "******** DemoMiddleware - before; args #{@args}"
    @app.call(deserialized_msg, delivery_info, metadata, handler)
    puts "******** DemoMiddleware - after"
  end
end

Sneakers.configure
Sneakers.middleware.use(DemoMiddleware, foo: :bar)

Sneakers.publish("{}", :to_queue => 'middleware-demo')
r = Sneakers::Runner.new([MiddlewareWorker])
r.run
