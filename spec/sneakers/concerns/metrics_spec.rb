require 'spec_helper'
require 'sneakers'
require 'logger'


class Foometrics
  include Sneakers::Concerns::Metrics
end

describe Sneakers::Concerns::Metrics do
  describe ".configure" do
    before do
      Foometrics.metrics = nil
    end

    it "should configure a default logger when included" do
      Foometrics.metrics.must_be_nil
      Foometrics.configure_metrics
      Foometrics.metrics.wont_be_nil
    end

    it "should supply accessible instance logger" do
      Foometrics.metrics.must_be_nil
      Foometrics.configure_metrics
      f = Foometrics.new
      f.metrics.must_equal Foometrics.metrics
      f.metrics.wont_be_nil
    end

    it "should configure a given metrics when specified" do
      Foometrics.metrics.must_be_nil
      o = Object.new
      Foometrics.configure_metrics(o)
      Foometrics.metrics.must_equal o
    end
  end
end

