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
      Foobar.logger.must_be_nil
      Foobar.configure_logger
      Foobar.logger.wont_be_nil
      Foobar.logger.formatter.must_equal Sneakers::Support::ProductionFormatter
    end

    it "should supply accessible instance logger" do
      Foobar.logger.must_be_nil
      Foobar.configure_logger
      f = Foobar.new
      f.logger.must_equal Foobar.logger
      f.logger.wont_be_nil
    end

    it "should configure a given logger when specified" do
      Foobar.logger.must_be_nil
      log = Logger.new(STDOUT)
      Foobar.configure_logger(log)
      Foobar.logger.must_equal log
    end
  end
end

