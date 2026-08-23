# frozen_string_literal: true

require "test_helper"
require "unit/support_load_probe_test" # single source of truth for the subprocess probe

# LEGACY SURFACE (test/legacy/, see the Rakefile).
#
# The v1 half of support_load_probe_test.rb: what the OLD entry points must
# still provide. Names and constants restored verbatim -- every assertion
# here is about a name 3.0 deletes, so repointing them at SnapDiff would
# have quietly turned this file into a duplicate of the canonical one.
class LegacyEntryPointProbeTest < ActiveSupport::TestCase
  # Alias-completeness probe (the f89cea2 bug class): each documented entry
  # point must define its advertised constants when it is the ONLY require —
  # the acyclic redesign once narrowed capybara_screenshot_diff/minitest so
  # consumers lost CapybaraScreenshotDiff::DSL, and only one CI matrix leg
  # noticed. capybara_screenshot_diff/cucumber is not probed: it calls
  # World(...) at load, which only exists inside cucumber's runtime context.
  # Documented user-facing constants that must stay EAGER (see
  # snap_diff/legacy_shims.rb's exception list): const_defined? never
  # triggers const_missing, so a lazy shim makes `defined?` feature
  # detection in adopter code silently return nil.
  EAGER_USER_FACING = %w[
    Capybara::Screenshot::Diff::Reporters::Default
    Capybara::Screenshot::Diff::Comparison
  ].freeze

  # The subset of EAGER_USER_FACING that must resolve under EVERY entry
  # point, canonical ones included -- these are read directly (a version
  # string, a struct), not just feature-detected, so a canonical-only app
  # still hits them. The test above only covers the four legacy entries,
  # which is how VERSION silently disappeared from six entry points when the
  # core stopped requiring capybara/screenshot/diff/version.rb: nothing
  # loaded the forwarder that assigned it, and const_missing does not fire
  # for a constant legacy_shims deliberately leaves out of its map.
  EAGER_EVERYWHERE = %w[
    Capybara::Screenshot::Diff::VERSION
    Capybara::Screenshot::Diff::Comparison
  ].freeze

  ENTRY_POINTS = {
    "capybara_screenshot_diff" => %w[
      CapybaraScreenshotDiff::DSL Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ] + EAGER_USER_FACING,
    "capybara_screenshot_diff/minitest" => %w[
      CapybaraScreenshotDiff::DSL CapybaraScreenshotDiff::Minitest::Assertions
      Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ] + EAGER_USER_FACING,
    "capybara_screenshot_diff/rspec" => %w[
      CapybaraScreenshotDiff::DSL Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ] + EAGER_USER_FACING,
    "capybara-screenshot-diff" => %w[
      CapybaraScreenshotDiff::DSL CapybaraScreenshotDiff::Minitest::Assertions
      Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ] + EAGER_USER_FACING
  }.freeze

  test "every documented entry point defines its advertised constants standalone" do
    failures = ENTRY_POINTS.filter_map do |entry, constants|
      probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{constants.inspect}.reject { |c| Object.const_defined?(c) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Entry point(s) no longer provide their advertised constants standalone:

      #{failures.join("\n")}
    MSG
  end

  # The legacy entries had the mirror image of the beta3 canonical hole:
  # some of them stopped loading the umbrella, so CapybaraScreenshotDiff.verify
  # and friends vanished while `defined?(CapybaraScreenshotDiff)` still passed.
  LEGACY_SESSION_SURFACE = %w[
    verify reset reporters finalize_reporters! assertions registry
    pending_screenshots_message
  ].freeze

  LEGACY_ENTRY_POINTS = %w[
    capybara-screenshot-diff
    snap_diff-capybara
    capybara_screenshot_diff
    capybara_screenshot_diff/minitest
    capybara_screenshot_diff/rspec
    capybara_screenshot_diff/cucumber
    capybara_screenshot_diff/static
    capybara/screenshot/diff
    capybara/screenshot/diff/cucumber
  ].freeze

  test "every legacy entry point keeps the CapybaraScreenshotDiff session surface" do
    failures = LEGACY_ENTRY_POINTS.filter_map do |entry|
      probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{LEGACY_SESSION_SURFACE.inspect}.reject { |m| CapybaraScreenshotDiff.respond_to?(m) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Legacy entry point(s) leave CapybaraScreenshotDiff half-present
      (the module answers `defined?` but not its own session methods):

      #{failures.join("\n")}
    MSG
  end

  # SnapDiff.start moved here out of the canonical CANONICAL_SURFACE gate: it
  # is defined in legacy_shims.rb and yields the two v1 config holders, so a
  # canonical gate demanding it fails the moment 3.0 deletes them. It is
  # still a documented v1 method, so the per-entry-point availability claim
  # the canonical gate used to make lives on here -- for the entries that
  # actually keep it. (What it yields is pinned in legacy_forwarders_test.)
  test "SnapDiff.start is available from every legacy entry point" do
    failures = LEGACY_ENTRY_POINTS.filter_map do |entry|
      probe(entry, <<~RUBY)
        require #{entry.inspect}
        abort("SnapDiff.start missing") unless SnapDiff.respond_to?(:start)
      RUBY
    end

    assert_empty failures, failures.join("\n")
  end

  # Every documented entry point, canonical and legacy. capybara_screenshot_diff/dsl
  # is listed only here: it is not in ENTRY_POINTS or LEGACY_ENTRY_POINTS, which
  # is exactly why it was the legacy entry that lost VERSION unnoticed.
  ALL_ENTRY_POINTS = (
    SupportLoadProbeTest::CANONICAL_ENTRY_POINTS.keys + LEGACY_ENTRY_POINTS + %w[capybara_screenshot_diff/dsl]
  ).uniq.freeze

  test "the eager user-facing constants resolve under every entry point" do
    failures = ALL_ENTRY_POINTS.filter_map do |entry|
      probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{EAGER_EVERYWHERE.inspect}.reject { |c| Object.const_defined?(c) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Entry point(s) no longer resolve constants that are supposed to be eager
      everywhere. `defined?` returns nil for these and const_missing does not
      fire, so adopter feature detection fails silently:

      #{failures.join("\n")}
    MSG
  end

  private

  def probe(entry, script)
    SupportLoadProbeTest.probe(entry, script)
  end
end
