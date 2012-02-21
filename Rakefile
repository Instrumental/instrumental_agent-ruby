require 'bundler/gem_helper'
require 'rspec/core/rake_task'
puts Dir["*-#{RUBY_PLATFORM}.gemspec"]
if !(gemspecs = Dir["*-#{RUBY_PLATFORM}.gemspec"]).empty?
  spec = File.basename(gemspecs.first, ".gemspec")
  Bundler::GemHelper.install_tasks(:name => spec)
else
  Bundler::GemHelper.install_tasks
end

task :default => :spec

RSpec::Core::RakeTask.new(:spec) do |spec|
  spec.pattern = 'spec/*_spec.rb'
  spec.rspec_opts = ['--color --backtrace']
end
