# Sneakers


```
      __
  ,--'  >  
  `=====   

```


A high-performance RabbitMQ background processing framework for
Ruby.


Sneakers is being used in production for both I/O and CPU intensive workloads, and have achieved the goals of high-performance and 0-maintenance, as designed.


Visit the [wiki](https://github.com/jondot/sneakers/wiki) for
complete docs.


[![Build Status](https://travis-ci.org/jondot/sneakers.svg?branch=master)](https://travis-ci.org/jondot/sneakers)


## Installation

Add this line to your application's Gemfile:

``` ruby
gem 'sneakers'
```

And then execute:

``` shell-session
$ bundle
```

Or install it yourself as:

``` shell-session
$ gem install sneakers
```

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
Sneakers.configure :metrics => Sneakers::Metrics::LoggingMetrics.new

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

# Compatibility

* Sneakers 1.1.x and up (using the new generation Bunny 2.x) - Ruby 2.x.x
* Sneakers 1.x.x and down - Ruby 1.9.x, 2.x.x

# Contributing

Fork, implement, add tests, pull request, get my everlasting thanks and a respectable place here :).


### Thanks:

To all Sneakers [Contributors](https://github.com/jondot/sneakers/graphs/contributors) - you make this happen, thanks!



# Copyright

Copyright (c) 2015 [Dotan Nahum](http://gplus.to/dotan) [@jondot](http://twitter.com/jondot). See [LICENSE](LICENSE.txt) for further details.
