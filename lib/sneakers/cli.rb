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
    method_option :front
    method_option :require

    desc "work FirstWorker,SecondWorker ... ,NthWorker", "Run workers"
    def work(workers)
      opts = {
        :daemonize => !options[:front]
      }
      unless opts[:daemonize]
        opts[:log] = STDOUT
      end

      Sneakers.configure(opts)
      puts Sneakers::Config

      require_boot File.expand_path(options[:require]) if options[:require]

      workers, missing_workers = Sneakers::Utils.parse_workers(workers)

      unless missing_workers.empty?
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

      pid = Sneakers::Config[:pid_path]

      say SNEAKERS
      say "Workers ....: #{em workers.join(', ')}"
      say "Log ........: #{em (Sneakers::Config[:log] == STDOUT ? 'Console' : Sneakers::Config[:log]) }"
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
        say Sneakers::Config.inspect
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
