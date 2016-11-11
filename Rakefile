require "bundler/gem_tasks"
require 'metric_fu'
require 'rake/testtask'

Rake::TestTask.new do |t|
  t.libs << "spec"
  t.test_files = FileList['spec/**/*_spec.rb']
  t.warning = false
end

task default: :test

