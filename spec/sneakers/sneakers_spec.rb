require 'spec_helper'
require 'sneakers'

class EnvWorker
  include Sneakers::Worker
  from_queue 'defaults'

  def work(msg)
  end
end


describe Sneakers do
  before do
    Sneakers.clear!
  end

  describe 'self' do
    it 'should have defaults set up' do
      _(Sneakers::CONFIG[:log]).must_equal(STDOUT)
    end

    it 'should configure itself' do
      Sneakers.configure
      _(Sneakers.logger).wont_be_nil
      _(Sneakers.configured?).must_equal(true)
    end
  end

  describe '.daemonize!' do
    it 'should set a logger to a default info level and not daemonize' do
      Sneakers.daemonize!
      _(Sneakers::CONFIG[:log]).must_equal('sneakers.log')
      _(Sneakers::CONFIG[:daemonize]).must_equal(true)
      _(Sneakers.logger.level).must_equal(Logger::INFO)
    end

    it 'should set a logger to a level given that level' do
      Sneakers.daemonize!(Logger::DEBUG)
      _(Sneakers.logger.level).must_equal(Logger::DEBUG)
    end
  end


  describe '.clear!' do
    it 'must reset dirty configuration to default' do
      _(Sneakers::CONFIG[:log]).must_equal(STDOUT)
      Sneakers.configure(:log => 'foobar.log')
      _(Sneakers::CONFIG[:log]).must_equal('foobar.log')
      Sneakers.clear!
      _(Sneakers::CONFIG[:log]).must_equal(STDOUT)
    end
  end


  describe '#setup_general_logger' do
    let(:logger_class) { ServerEngine::DaemonLogger }

    it 'should detect a string and configure a logger' do
      Sneakers.configure(:log => 'sneakers.log')
      _(Sneakers.logger.kind_of?(logger_class)).must_equal(true)
    end

    it 'should detect a file-like thing and configure a logger' do
      Sneakers.configure(:log => STDOUT)
      _(Sneakers.logger.kind_of?(logger_class)).must_equal(true)
    end

    it 'should detect an actual logger and configure it' do
      logger = Logger.new(STDOUT)
      Sneakers.configure(:log => logger)
      _(Sneakers.logger).must_equal(logger)
    end
  end

end

