require 'spec_helper'
require 'sneakers'
require 'logger'


class Foobar
  include Sneakers::Concerns::Logging
end

describe Sneakers::Concerns::Logging do
  describe ".configure" do
    before do
      Foobar.logger = nil
    end

    it "should configure a default logger when included" do
      _(Foobar.logger).must_be_nil
      Foobar.configure_logger
      _(Foobar.logger).wont_be_nil
      _(Foobar.logger.formatter).must_equal Sneakers::Support::ProductionFormatter
    end

    it "should supply accessible instance logger" do
      _(Foobar.logger).must_be_nil
      Foobar.configure_logger
      f = Foobar.new
      _(f.logger).must_equal Foobar.logger
      _(f.logger).wont_be_nil
    end

    it "should configure a given logger when specified" do
      _(Foobar.logger).must_be_nil
      log = Logger.new(STDOUT)
      Foobar.configure_logger(log)
      _(Foobar.logger).must_equal log
    end
  end
end

