require 'thor'
require 'sneakers/runner'


#
# $ sneakers run TitleWorker,FooWorker
# $ sneakers stop
# $ sneakers recycle
# $ sneakers reload
# $ sneakers init
#
#
module Sneakers
  class CLI < Thor

    SNEAKERS=<<-EOF

        __
    ,--'  >  Sneakers
    `=====

    EOF

    BANNER = SNEAKERS

    method_option :debug
    method_option :daemonize
    method_option :log
    method_option :pid_path
    method_option :require

    desc "work FirstWorker,SecondWorker ... ,NthWorker", "Run workers"
    def work(workers = "")
      opts = {
        :daemonize => !!options[:daemonize]
      }

      opts[:log] = options[:log] || (opts[:daemonize] ? 'sneakers.log' : STDOUT)
      opts[:pid_path] = options[:pid_path] if options[:pid_path]

      if opts[:daemonize]
        puts "*** DEPRACATED: self-daemonization '--daemonize' is considered a bad practice, which is why this feature will be removed in future versions. Please run Sneakers in front, and use things like upstart, systemd, or supervisor to manage it as a daemon."
      end


      Sneakers.configure(opts)

      require_boot File.expand_path(options[:require]) if options[:require]

      if workers.empty?
        workers = Sneakers::Worker::Classes
      else
        workers, missing_workers = Sneakers::Utils.parse_workers(workers)
      end

      unless missing_workers.nil? || missing_workers.empty?
        say "Missing workers: #{missing_workers.join(', ')}" if missing_workers
        say "Did you `require` properly?"
        return
      end

      if workers.empty?
        say <<-EOF
        Error: No workers found.
        Please require your worker classes before specifying in CLI

          $ sneakers run FooWorker
                         ^- require this in your code

        EOF
        return
      end

      r = Sneakers::Runner.new(workers)

      pid = Sneakers::CONFIG[:pid_path]

      say SNEAKERS
      say "Workers ....: #{em workers.join(', ')}"
      say "Log ........: #{em (Sneakers::CONFIG[:log] == STDOUT ? 'Console' : Sneakers::CONFIG[:log]) }"
      say "PID ........: #{em pid}"
      say ""
      say (" "*31)+"Process control"
      say "="*80
      say "Stop (nicely) ..............: kill -SIGTERM `cat #{pid}`"
      say "Stop (immediate) ...........: kill -SIGQUIT `cat #{pid}`"
      say "Restart (nicely) ...........: kill -SIGUSR1 `cat #{pid}`"
      say "Restart (immediate) ........: kill -SIGHUP `cat #{pid}`"
      say "Reconfigure ................: kill -SIGUSR2 `cat #{pid}`"
      say "Scale workers ..............: reconfigure, then restart"
      say "="*80
      say ""

      if options[:debug]
        say "==== configuration ==="
        say Sneakers::CONFIG.inspect
        say "======================"
      end

      r.run
    end


  private
    def require_boot(file)
      load file
    end

    def em(text)
      shell.set_color(text, nil, true)
    end

    def ok(detail=nil)
      text = detail ? "OK, #{detail}." : "OK."
      say text, :green
    end

    def error(detail)
      say detail, :red
    end
  end
end
