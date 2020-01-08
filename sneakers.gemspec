#!/usr/bin/env gem build
# encoding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'sneakers/version'

Gem::Specification.new do |gem|
  gem.name          = 'sneakers'
  gem.version       = Sneakers::VERSION
  gem.authors       = ['Dotan Nahum']
  gem.email         = ['jondotan@gmail.com']
  gem.description   = %q( Fast background processing framework for Ruby and RabbitMQ )
  gem.summary       = %q( Fast background processing framework for Ruby and RabbitMQ )
  gem.homepage      = 'http://sneakers.io'
  gem.license       = 'MIT'
  gem.required_ruby_version = Gem::Requirement.new(">= 2.2")

  gem.files         = `git ls-files`.split($/).reject { |f| f == 'Gemfile.lock' }
  gem.executables   = gem.files.grep(/^bin/).
                        reject { |f| f =~ /^bin\/ci/ }.
                        map { |f| File.basename(f) }
  gem.test_files    = gem.files.grep(/^(test|spec|features)\//)
  gem.require_paths = ['lib']

  gem.add_dependency 'serverengine', '~> 2.1.0'
  gem.add_dependency 'bunny', '~> 2.14'
  gem.add_dependency 'concurrent-ruby', '~> 1.0'
  gem.add_dependency 'thor'
  gem.add_dependency 'rake', '>= 12.3', '< 14.0'

  # for integration environment (see .travis.yml and integration_spec)
  gem.add_development_dependency 'rabbitmq_http_api_client'
  gem.add_development_dependency 'redis'

  gem.add_development_dependency 'rake', '~> 12.3'
  gem.add_development_dependency 'minitest', '~> 5.11'
  gem.add_development_dependency 'rr', '~> 1.2.1'
  gem.add_development_dependency 'unparser', '0.2.2' # keep below 0.2.5 for ruby 2.0 compat.
  gem.add_development_dependency 'metric_fu', '~> 4.12'
  gem.add_development_dependency 'simplecov', '~> 0.16'
  gem.add_development_dependency 'simplecov-rcov-text'
  gem.add_development_dependency 'guard', '~> 2.15'
  gem.add_development_dependency 'guard-minitest', '~> 2.4'
  gem.add_development_dependency 'pry-byebug', '~> 3.7'
end
