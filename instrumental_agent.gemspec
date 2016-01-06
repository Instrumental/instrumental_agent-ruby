$:.push File.expand_path("../lib", __FILE__)
require "instrumental/version"

Gem::Specification.new do |s|
  s.name        = "instrumental_agent"
  s.version     = Instrumental::VERSION
  s.authors     = ["Elijah Miller", "Christopher Zelenak", "Kristopher Chambers", "Matthew Hassfurder"]
  s.email       = ["support@instrumentalapp.com"]
  s.homepage    = "http://github.com/expectedbehavior/instrumental_agent"
  s.summary     = %q{Agent for reporting data to instrumentalapp.com}
  s.description = %q{Track anything.}
  s.license     = "MIT"


  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_development_dependency("rake", [">= 0"])
  s.add_development_dependency("rspec", ["~> 3.0"])
  s.add_development_dependency("fuubar", [">= 0"])
end
