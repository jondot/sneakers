require 'bundler/setup'
require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
end

require 'minitest/autorun'

require 'rr'

Dir[File.join(File.dirname(__FILE__), 'support/**/*.rb')].each { |f| require f }
