# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capybara/screenshot/diff/version'

Gem::Specification.new do |spec|
  spec.name          = 'capybara-screenshot-diff'
  spec.version       = Capybara::Screenshot::Diff::VERSION
  spec.authors       = ['Uwe Kubosch']
  spec.email         = ['uwe@kubosch.no']

  spec.summary       = 'Track your GUI changes with diff assertions'
  spec.description   = 'Save screen shots and track changes with graphical diff'
  spec.homepage      = 'https://github.com/donv/capybara-screenshot-diff'
  spec.license       = 'MIT'

  # Prevent pushing this gem to RubyGems.org by setting 'allowed_push_host', or
  # delete this section to allow pushing this gem to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = 'https://rubygems.org/'
  else
    fail 'RubyGems 2.0 or newer is required to protect against public gem push.'
  end

  spec.files         = `git ls-files -z`.split("\x0")
      .reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'capybara', '~> 2.0'

  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'minitest-reporters'
  spec.add_development_dependency 'rubocop', '~> 0.39'
end
