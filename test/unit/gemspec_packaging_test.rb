# frozen_string_literal: true

require "test_helper"

# The gemspec's `spec.files` allow-list is the one part of the release that no
# other test looks at, and it has shipped broken twice: a missing
# Bundler.require entry file makes `gem "..."` load NOTHING and fail later with
# a confusing NameError, far from the cause. These assertions are about the
# PACKAGED file list, not about the working tree.
class GemspecPackagingTest < ActiveSupport::TestCase
  GEMSPEC_PATH = File.expand_path("../../capybara-screenshot-diff.gemspec", __dir__)

  def spec
    @spec ||= Gem::Specification.load(GEMSPEC_PATH)
  end

  # Bundler requires the gem's OWN NAME. Each published name needs a file that
  # matches it, or `Bundler.require` silently no-ops for that name.
  test "ships a Bundler.require entry file for both published gem names" do
    assert_includes spec.files, "lib/capybara-screenshot-diff.rb"
    assert_includes spec.files, "lib/snap_diff-capybara.rb"
  end

  test "ships the files rubygems.org and a consumer read" do
    ["README.md", "LICENSE.txt", "CHANGELOG.md", "docs/UPGRADING.md", "docs/snapdiff.md"]
      .each { |file| assert_includes spec.files, file }
  end

  # Contributor-only docs describe releasing this gem and bin/dtest, neither of
  # which a consumer has.
  test "ships no contributor-only docs" do
    refute_includes spec.files, "docs/RELEASE_PREP.md"
    refute_includes spec.files, "docs/docker-testing.md"
  end

  test "ships no build or development files" do
    cruft = spec.files.grep_v(%r{\A(lib/|docs/|README\.md\z|LICENSE\.txt\z|CHANGELOG\.md\z)})
    assert_empty cruft
  end

  # Every driver is an optional require. Adding a runtime dependency here is a
  # decision, not an accident -- 2.1 makes ruby-vips one deliberately.
  test "declares capybara as its only runtime dependency" do
    runtime = spec.dependencies.select { |dependency| dependency.type == :runtime }
    assert_equal ["capybara"], runtime.map(&:name)
  end
end
