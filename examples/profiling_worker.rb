$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'logger'


profiling = ARGV[0]
messages = 100_000


if profiling
  require 'ruby-prof'
  messages /= 100 # profiling makes everything much slower (around 300req/s)
end

Sneakers.configure
Sneakers.logger.level = Logger::ERROR

Sneakers::Worker.configure_logger(Logger.new('/dev/null'))

puts "feeding messages in"
messages.times {
  Sneakers.publish("{}", :to_queue => 'downloads')
}
puts "done"


class ProfilingWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :ack => true,
             :threads => 50,
             :prefetch => 50,
             :timeout_job_after => 1,
             :exchange => 'sneakers',
             :heartbeat => 5,
             :amqp_heartbeat => 10
  def work(msg)
    ack!
  end
end



r = Sneakers::Runner.new([ProfilingWorker])

# ctrl-c and Ruby 2.0 breaks signal handling
# Sidekiq has same issues
# https://github.com/mperham/sidekiq/issues/728
#
# so we use a timeout and a thread that kills profiling
if profiling
  puts "profiling start"
  RubyProf.start


  Thread.new do
    sleep 10
    puts "stopping profiler"
    result = RubyProf.stop

    # Print a flat profile to text
    printer = RubyProf::FlatPrinter.new(result)
    printer.print(STDOUT)
    exit(0)
  end
end

r.run
