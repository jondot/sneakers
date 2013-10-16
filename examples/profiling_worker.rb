$: << File.expand_path('../lib', File.dirname(__FILE__))
require 'sneakers'
require 'sneakers/runner'
require 'ruby-prof'


puts "feeding messages in"
1000.times {
  Sneakers.publish("{}", :to_queue => 'downloads')
puts "done"


class ProfilingWorker
  include Sneakers::Worker
  from_queue 'downloads',
             :env => '',
             :durable => false,
             :ack => true,
             :threads => 50,
             :prefetch => 50,
             :timeout_job_after => 1,
             :exchange => 'dummy',
             :heartbeat_interval => 5
  def work(msg)
    ack!
  end
end



r = Sneakers::Runner.new
Sneakers::Worker.configure_logger(Logger.new('/dev/null'))

# ctrl-c and Ruby 2.0 breaks signal handling
# Sidekiq has same issues
# https://github.com/mperham/sidekiq/issues/728
#
# so we use a timeout and a thread that kills profiling
puts "profiling start"
RubyProf.start

Thread.new do
  sleep 10
  puts "stopping profiler"
  result = RubyProf.stop

  # Print a flat profile to text
  printer = RubyProf::FlatPrinter.new(result)
  printer.print(STDOUT)
  r.stop
  exit(0)
end

r.run([ ProfilingWorker ])

