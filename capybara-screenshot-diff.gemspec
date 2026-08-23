# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "snap_diff/version"

Gem::Specification.new do |spec|
  spec.name = "capybara-screenshot-diff"
  spec.version = SnapDiff::VERSION
  spec.authors = ["Uwe Kubosch"]
  spec.email = ["uwe@kubosch.no"]
  spec.summary = "Track your GUI changes with diff assertions"
  spec.description = "Save screen shots and track changes with graphical diff"
  spec.homepage = "https://github.com/snap-diff/snap_diff-capybara"
  spec.required_ruby_version = ">= 3.2"
  spec.license = "MIT"
  spec.metadata["allowed_push_host"] = "https://rubygems.org/"
  # Allow-list: everything a consumer needs at runtime plus the shipped docs.
  # Build/dev files (gems.rb, Rakefile, the gemspec itself, tests, CI) stay out.
  spec.files = `git ls-files -z`.split("\x0")
    .grep(%r{\A(lib/|docs/|README\.md\z|LICENSE\.txt\z|CHANGELOG\.md\z)})
    .grep_v(%r{\Adocs/RELEASE_PREP\.md\z}) # maintainer-only, not user documentation

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "actionpack", ">= 7.1", "< 9"
  spec.add_development_dependency "activesupport", ">= 7.1", "< 9"
  spec.add_runtime_dependency "capybara", ">= 2", "< 4"
  # 2.1 removed the driver abstraction: libvips is the only backend, so the
  # gem that binds it is a hard dependency rather than something the user is
  # told to add. Without this an install resolves fine and then dies at the
  # first comparison -- a resolver error is the better failure.
  #
  # ruby-vips 2.x is the current major line; the gem itself needs system
  # libvips >= 8.2, which no gemspec constraint can express -- see
  # docs/drivers.md for the system package.
  spec.add_runtime_dependency "ruby-vips", ">= 2.0", "< 3"
end
