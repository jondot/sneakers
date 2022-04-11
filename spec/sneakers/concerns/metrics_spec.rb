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
      _(Foometrics.metrics).must_be_nil
      Foometrics.configure_metrics
      _(Foometrics.metrics).wont_be_nil
    end

    it "should supply accessible instance logger" do
      _(Foometrics.metrics).must_be_nil
      Foometrics.configure_metrics
      f = Foometrics.new
      _(f.metrics).must_equal Foometrics.metrics
      _(f.metrics).wont_be_nil
    end

    it "should configure a given metrics when specified" do
      _(Foometrics.metrics).must_be_nil
      o = Object.new
      Foometrics.configure_metrics(o)
      _(Foometrics.metrics).must_equal o
    end
  end
end

