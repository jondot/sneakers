require 'spec_helper'
require 'sneakers'



describe Sneakers do
  before do
    Sneakers.clear!
  end

  describe 'self' do
    it 'should have defaults set up' do
      Sneakers::Config[:log].must_equal('sneakers.log')
    end

    it 'should configure itself' do
      Sneakers.configure
      Sneakers.logger.wont_be_nil
    end
  end

  describe '.run_at_front!' do
    it 'should set a logger to a default info level and not daemonize' do
      Sneakers.run_at_front!
      Sneakers::Config[:log].must_equal(STDOUT)
      Sneakers::Config[:daemonize].must_equal(false)
      Sneakers.logger.level.must_equal(Logger::INFO)
    end

    it 'should set a logger to a level given that level' do
      Sneakers.run_at_front!(Logger::DEBUG)
      Sneakers.logger.level.must_equal(Logger::DEBUG)
    end
  end

  describe '.clear!' do
    it 'must reset dirty configuration to default' do
      Sneakers::Config[:log].must_equal('sneakers.log')
      Sneakers.configure(:log => 'foobar.log')
      Sneakers::Config[:log].must_equal('foobar.log')
      Sneakers.clear!
      Sneakers::Config[:log].must_equal('sneakers.log')
    end
  end

end

