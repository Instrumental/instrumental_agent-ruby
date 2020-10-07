$:.push File.expand_path("../lib", __FILE__)
require "instrumental/version"

Gem::Specification.new do |s|
  s.name        = "instrumental_agent"
  s.version     = Instrumental::VERSION
  s.authors     = ["Expected Behavior"]
  s.email       = ["support@instrumentalapp.com"]
  s.homepage    = "http://github.com/instrumental/instrumental_agent-ruby"
  s.summary     = %q{Custom metric monitoring for Ruby applications via Instrumental}
  s.description = %q{This agent supports Instrumental custom metric monitoring for Ruby applications. It provides high-data reliability at high scale, without ever blocking your process or causing an exception.}
  s.license     = "MIT"
  s.required_ruby_version = '>= 2.5.7'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_runtime_dependency("metrician", [">= 0"])

  s.add_development_dependency("pry", [">= 0"])
  s.add_development_dependency("rake", [">= 0"])
  s.add_development_dependency("rspec", ["~> 3.0"])
  s.add_development_dependency("fuubar", [">= 0"])
  s.add_development_dependency("timecop", [">= 0"])
end
