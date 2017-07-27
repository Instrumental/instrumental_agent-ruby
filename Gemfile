source "https://rubygems.org"

gemspec
ruby_engine = defined?(RUBY_ENGINE) && RUBY_ENGINE
if RUBY_VERSION < "1.9" && !%w{jruby rbx}.include?(ruby_engine)
  # Built and installed via ext/mkrf_conf.rb
  gem 'system_timer', '~> 1.2'
end

# fixes 2.3.0 ffi bundle error
gem 'ffi', '~> 1.0.11'