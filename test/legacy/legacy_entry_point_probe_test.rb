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

  # The canonical half of this claim lives in support_load_probe_test.rb; the
  # v1 entry points get the same treatment here because the cycle they used
  # to load through (drivers.rb <-> utils.rb) shouted at every user whose
  # suite runs with warnings on -- which Rake::TestTask does by default.
  test "no legacy entry point emits a circular require warning under -w" do
    failures = LEGACY_ENTRY_POINTS.filter_map do |entry|
      noise = SupportLoadProbeTest.verbose_load(entry).lines.grep(/circular require/)
      "require \"#{entry}\" ->\n#{noise.join}" unless noise.empty?
    end

    assert_empty failures, <<~MSG
      Legacy entry point(s) load through a `require` cycle:

      #{failures.join("\n")}
    MSG
  end

  # Every legacy constant a consumer might touch, as of v1.12.0's surface.
  # UPGRADING.md tells adopters to migrate their `require` line FIRST and
  # rename constants afterwards, so this half-migrated state -- canonical
  # require, v1 constants -- is a supported one, not an exotic edge case.
  # It used to kill a whole suite at load on `Capybara::Screenshot::Os`.
  LEGACY_CONSTANTS = %w[
    Capybara::Screenshot::Os
    Capybara::Screenshot::BrowserHelpers
    Capybara::Screenshot::Screenshoter
    Capybara::Screenshot::Diff::Vcs
    Capybara::Screenshot::Diff::StableScreenshoter
    Capybara::Screenshot::Diff::ImagePreprocessor
    Capybara::Screenshot::Diff::AreaCalculator
    Capybara::Screenshot::Diff::AnnotationService
    Capybara::Screenshot::Diff::Utils
    Capybara::Screenshot::Diff::ScreenshotMatcher
    Capybara::Screenshot::Diff::Drivers
    Capybara::Screenshot::Diff::Drivers::BaseDriver
    Capybara::Screenshot::Diff::Drivers::ChunkyPNGDriver
    Capybara::Screenshot::Diff::ImageCompare
    Capybara::Screenshot::Diff::Difference
    Capybara::Screenshot::Diff::Comparison
    Capybara::Screenshot::Diff::VERSION
    Capybara::Screenshot::Diff::LOADED_DRIVERS
    Capybara::Screenshot::Diff::AVAILABLE_DRIVERS
    Capybara::Screenshot::Diff::Reporters::Default
    Region
    CapybaraScreenshotDiff::RED_RGBA
    CapybaraScreenshotDiff::ORANGE_RGBA
    CapybaraScreenshotDiff::SnapManager
    CapybaraScreenshotDiff::Snap
    CapybaraScreenshotDiff::ScreenshotNamer
    CapybaraScreenshotDiff::AttemptsReporter
    CapybaraScreenshotDiff::BacktraceFilter
    CapybaraScreenshotDiff::ErrorWithFilteredBacktrace
    CapybaraScreenshotDiff::ScreenshotAssertion
    CapybaraScreenshotDiff::AssertionRegistry
    CapybaraScreenshotDiff::CapybaraScreenshotDiffError
    CapybaraScreenshotDiff::ExpectationNotMet
    CapybaraScreenshotDiff::UnstableImage
    CapybaraScreenshotDiff::WindowSizeMismatchError
    CapybaraScreenshotDiff::DSL
    CapybaraScreenshotDiff::Minitest::Assertions
    CapybaraScreenshotDiff::Reporters::HTML
  ].freeze

  test "every legacy constant resolves under a canonical-only require" do
    failures = ALL_ENTRY_POINTS.filter_map do |entry|
      probe(entry, <<~RUBY)
        ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "1"
        require #{entry.inspect}
        # Resolvability only -- same-object identity is pinned separately by
        # test/legacy/namespace_forwarding_test.rb.
        broken = #{LEGACY_CONSTANTS.inspect}.filter_map do |name|
          begin
            Object.const_get(name)
            nil
          rescue NameError => e
            "\#{name}: \#{e.message.lines.first.strip}"
          end
        end
        abort(broken.join("\n")) unless broken.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Legacy constant(s) do not resolve under these entry points. A half-
      migrated app -- canonical require, v1 constants, exactly what
      UPGRADING.md walks users into -- dies on the first reference:

      #{failures.join("\n")}
    MSG
  end

  # Vips is optional, so its driver leaf only has to resolve where the
  # library is actually installed.
  test "the vips driver leaf resolves under a canonical-only require" do
    skip "vips not available in this environment" unless SnapDiff::Drivers.available.include?(:vips)

    assert_nil SupportLoadProbeTest.probe("snap_diff", <<~RUBY)
      ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "1"
      require "snap_diff"
      Object.const_get("Capybara::Screenshot::Diff::Drivers::VipsDriver")
    RUBY
  end

  # A legacy name whose replacement genuinely cannot load must say so in the
  # user's vocabulary -- UPGRADING.md -- not leak a bare "uninitialized
  # constant SnapDiff::Something" from gem internals.
  test "an unloadable legacy constant points at the upgrade guide" do
    out, status = Open3.capture2e(
      RbConfig.ruby, "-Ilib", "-e", <<~RUBY, chdir: File.expand_path("../..", __dir__)
        ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "1"
        require "snap_diff"
        mod = Module.new
        SnapDiff::LegacyShims.install(mod, "Old::Prefix", {Gone: "SnapDiff::NoSuchThing"})
        begin
          mod::Gone
        rescue NameError => e
          puts e.message
        end
      RUBY
    )

    assert status.success?, out
    assert_includes out, "SnapDiff::NoSuchThing"
    assert_includes out, "docs/UPGRADING.md"
    refute_includes out, "Reference `SnapDiff::NoSuchThing` directly",
      "must not advise referencing a name we just failed to load"
  end

  private

  def probe(entry, script)
    SupportLoadProbeTest.probe(entry, script)
  end
end
