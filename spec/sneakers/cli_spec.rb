require 'spec_helper'
require 'sneakers'
require 'sneakers/cli'
require 'sneakers/runner'

describe Sneakers::CLI do
  describe "#work" do
    before do
      any_instance_of(Sneakers::Runner) do |runner|
        stub(runner).run{ true }
      end
    end

    after do
      # require cleanup
      Object.send(:remove_const, :TitleScraper) if Object.constants.include?(:TitleScraper)
    end

    describe 'with dirty class loading' do
      it "should perform a run" do
        any_instance_of(Sneakers::Runner) do |runner|
          mock(runner).run{ true }
        end
        out = capture_io{ Sneakers::CLI.start [
          'work',
          "TitleScraper",
          "--require=#{File.expand_path('../fixtures/require_worker.rb', File.dirname(__FILE__))}"
        ]}.join ''

        out.must_match(/Workers.*:.*TitleScraper.*/)

      end

      it "should be able to run as front-running process" do
        out = capture_io{ Sneakers::CLI.start [
          'work',
          "TitleScraper",
          "--require=#{File.expand_path('../fixtures/require_worker.rb', File.dirname(__FILE__))}"
        ]}.join ''

        out.must_match(/Log.*Console/)
      end

      it "should be able to run as daemonized process" do
        out = capture_io{ Sneakers::CLI.start [
          'work',
          "TitleScraper",
          "--daemonize",
          "--require=#{File.expand_path('../fixtures/require_worker.rb', File.dirname(__FILE__))}"
        ]}.join ''

        out.must_match(/sneakers.log/)
      end
    end

    it "should fail when no workers found" do
      out = capture_io{ Sneakers::CLI.start ['work', 'TitleScraper'] }.join ''
      out.must_match(/Missing workers: TitleScraper/)
    end

    it "should run all workers when run without specifying any" do
      out = capture_io{ Sneakers::CLI.start [
        "work",
        "--require=#{File.expand_path("../fixtures/require_worker.rb", File.dirname(__FILE__))}"
      ]}.join ''

      out.must_match(/Workers.*:.*TitleScraper.*/)
    end

    after do
      # require cleanup
      Object.send(:remove_const, :TitleScraper) if Object.constants.include?(:TitleScraper)
    end
  end
end
