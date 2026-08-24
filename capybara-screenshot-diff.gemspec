# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "snap_diff/version"

Gem::Specification.new do |spec|
  spec.name = "capybara-screenshot-diff"
  spec.version = SnapDiff::VERSION
  spec.authors = ["Uwe Kubosch"]
  spec.email = ["uwe@kubosch.no"]
  spec.summary = "Visual regression testing for Capybara — screenshot diffs in your test suite"
  spec.description = "Take screenshots in your Capybara tests, commit the baselines to git, " \
    "and let your suite fail on unintended visual changes. Runs offline, no SaaS."
  spec.homepage = "https://github.com/snap-diff/snap_diff-capybara"
  spec.required_ruby_version = ">= 3.2"
  spec.license = "MIT"
  spec.metadata["allowed_push_host"] = "https://rubygems.org/"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/master/docs/snapdiff.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  # Allow-list: everything a consumer needs at runtime plus the shipped docs.
  # Build/dev files (gems.rb, Rakefile, the gemspec itself, tests, CI) stay out.
  spec.files = `git ls-files -z`.split("\x0")
    .grep(%r{\A(lib/|docs/|README\.md\z|LICENSE\.txt\z|CHANGELOG\.md\z)})
    # Contributor docs: they describe releasing this gem and running its own suite
    # via bin/dtest, which is not packaged. Nothing a consumer can act on.
    .grep_v(%r{\Adocs/(RELEASE_PREP|docker-testing)\.md\z})

  # No executables: the allow-list above never matches exe/, so bindir and
  # executables would always be empty.
  spec.require_paths = ["lib"]

  spec.add_development_dependency "actionpack", ">= 7.1", "< 9"
  spec.add_development_dependency "activesupport", ">= 7.1", "< 9"
  spec.add_runtime_dependency "capybara", ">= 2", "< 4"
end
