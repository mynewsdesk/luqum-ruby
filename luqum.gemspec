require_relative "lib/luqum/version"

Gem::Specification.new do |spec|
  spec.name          = "luqum"
  spec.version       = Luqum::VERSION
  spec.authors       = ["luqum-ruby contributors"]
  spec.summary       = "Lucene query parser and transformer (Ruby port of the Python luqum library)"
  spec.description   = "A Ruby library to parse, inspect, and transform Lucene query syntax. Ported from the Python luqum library."
  spec.license       = "LGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "LICENSE*", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal"
end
