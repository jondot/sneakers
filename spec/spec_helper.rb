require 'bundler/setup'
require 'simplecov'
require 'resolv'

SimpleCov.start do
  add_filter "/spec/"
end

require 'minitest/autorun'

require 'rr'

def compose_or_localhost(key)
  Resolv::DNS.new.getaddress(key)
rescue
  "localhost"
end



