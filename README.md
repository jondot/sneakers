# Sneakers

[![Build Status](https://travis-ci.org/jondot/sneakers.svg?branch=master)](https://travis-ci.org/jondot/sneakers)

```
      __
  ,--'  >
  `=====

```

A high-performance RabbitMQ background processing framework for
Ruby.

Sneakers is being used in production for both I/O and CPU intensive workloads, and have achieved the goals of high-performance and 0-maintenance, as designed.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'sneakers'
```

And then execute:

```shell-session
$ bundle
```

Or install it yourself as:

```shell-session
$ gem install sneakers
```

## Documentation

A quick start guide is available in the section below.

Visit the [wiki](https://github.com/jondot/sneakers/wiki) for more detailed
documentation and [GitHub releases](https://github.com/jondot/sneakers/releases) for release
notes.

A [change log](./ChangeLog.md) is also available.

## Quick start

Set up a Gemfile

```ruby
source 'https://rubygems.org'
gem 'sneakers'
gem 'json'
gem 'redis'
```

How do we add a worker? Firstly create a file and name it as `boot.rb`
then create a worker named as `Processor`.

> touch boot.rb

```ruby
require 'sneakers'
require 'redis'
require 'json'

$redis = Redis.new

class Processor
  include Sneakers::Worker
  from_queue :logs


  def work(msg)
    err = JSON.parse(msg)
    if err["type"] == "error"
      $redis.incr "processor:#{err["error"]}"
    end

    ack!
  end
end
```

Let's test it out quickly from the command line:

```shell-session
$ sneakers work Processor --require boot.rb
```

We just told Sneakers to spawn a worker named `Processor`, but first `--require` a file that we dedicate to setting up environment, including workers and what-not.

If you go to your RabbitMQ admin now, you'll see a new queue named `logs` was created. Push a couple messages like below:

```javascript
{
   "type": "error",
   "message": "HALP!",
   "error": "CODE001"
}
```

Publish a message with the [bunny](https://github.com/ruby-amqp/bunny) gem RabbitMQ client:

```ruby
require 'bunny'

conn = Bunny.new
conn.start

ch = conn.create_channel
ch.default_exchange.publish({ type: 'error', message: 'HALP!', error: 'CODE001' }.to_json, routing_key: 'logs')

conn.close
```

And this is the output you should see at your terminal.

```
2013-10-11T19:26:36Z p-4718 t-ovqgyb31o DEBUG: [worker-logs:1:213mmy][#<Thread:0x007fae6b05cc58>][logs][{:prefetch=>10, :durable=>true, :ack=>true, :heartbeat_interval=>2, :exchange=>"sneakers"}] Working off: log log
2013-10-11T19:26:36Z p-4718 t-ovqgyrxu4 INFO: log log
2013-10-11T19:26:40Z p-4719 t-ovqgyb364 DEBUG: [worker-logs:1:h23iit][#<Thread:0x007fae6b05cd98>][logs][{:prefetch=>10, :durable=>true, :ack=>true, :heartbeat_interval=>2, :exchange=>"sneakers"}] Working off: log log
2013-10-11T19:26:40Z p-4719 t-ovqgyrx8g INFO: log log
```

We'll count errors and error types with Redis.

``` shell-session
$ redis-cli monitor
1381520329.888581 [0 127.0.0.1:49182] "incr" "processor:CODE001"
```

We're basically done with the ceremonies and all is left is to do some real work.

### Looking at metrics

Let's use the `logging_metrics` provider just for the sake of fun of seeing the metrics as they happen.

```ruby
# boot.rb
require 'sneakers'
require 'redis'
require 'json'
require 'sneakers/metrics/logging_metrics'
Sneakers.configure(metrics: Sneakers::Metrics::LoggingMetrics.new)

# ... rest of code
```

Now push a message again and you'll see:

```
2013-10-11T19:44:37Z p-9219 t-oxh8owywg INFO: INC: work.Processor.started
2013-10-11T19:44:37Z p-9219 t-oxh8owywg INFO: TIME: work.Processor.time 0.00242
2013-10-11T19:44:37Z p-9219 t-oxh8owywg INFO: INC: work.Processor.handled.ack
```

Which increments `started` and `handled.ack`, and times the work unit.

From here, you can continue over to the
[Wiki](https://github.com/jondot/sneakers/wiki)

# Docker

If you use Docker, there's some benefits to be had and you can use both
`docker` and `docker-compose` with this project, in order to run tests,
integration tests or a sample worker without setting up RabbitMQ or the
environment needed locally on your development box.

* To build a container run `docker build . -t sneakers_sneakers`
* To run non-integration tests within a docker container, run `docker run --rm
  sneakers_sneakers:latest`
* To run full integration tests within a docker topology including RabbitMQ,
  Redis (for integration worker) run `scripts/local_integration`, which will
  use docker-compose to orchestrate the topology and the sneakers Docker image
  to run the tests
* To run a sample worker within Docker, try the `TitleScraper` example by
  running `script/local_worker`. This will use docker-compose as well. It will
  also help you get a feeling for how to run Sneakers in a Docker based
  production environment
* Use `Dockerfile.slim` instead of `Dockerfile` for production docker builds.
  It generates a more compact image, while the "regular" `Dockerfile` generates
  a fatter image - yet faster to iterate when developing

# Compatibility

* Sneakers 2.7.x and later (using Bunny 2.9) - Ruby 2.2.x
* Sneakers 1.1.x and later (using Bunny 2.x) - Ruby 2.x
* Sneakers 1.x.x and earlier - Ruby 1.9.x, 2.x

# Contributing

Fork, implement, add tests, pull request, get my everlasting thanks and a respectable place here :).

### Thanks:

To all Sneakers [Contributors](https://github.com/jondot/sneakers/graphs/contributors) - you make this happen, thanks!

# Copyright

Copyright (c) 2015-2018 [Dotan Nahum](http://gplus.to/dotan) [@jondot](http://twitter.com/jondot). See [LICENSE](LICENSE.txt) for further details.
