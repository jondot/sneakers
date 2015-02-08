require 'bundler/setup'
require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
end

require 'minitest/autorun'

require 'rr'




