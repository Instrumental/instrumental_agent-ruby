source "https://rubygems.org"

gemspec

if RUBY_VERSION < "1.9" && !%w{jruby rbx}.include?(RUBY_ENGINE)
  # Built and installed via ext/mkrf_conf.rb
  gem 'system_timer', '~> 1.2'
end
