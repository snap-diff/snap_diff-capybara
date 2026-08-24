# frozen_string_literal: true

require "test_helper"
require "open3"
require "snap_diff/deprecation"

# LEGACY SURFACE (test/legacy/, see the Rakefile): SnapDiff::Deprecation is
# the channel that announces the v1 shims, so snap_diff/deprecation.rb and
# this file are deleted together with lib/capybara* in 2.1.
class SnapDiffDeprecationTest < ActiveSupport::TestCase
  def setup
    SnapDiff::Deprecation.reset!
    @original_silence = SnapDiff.silence_deprecations
    @original_env = ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"]
    # These examples assert on the unsilenced default warning behavior, so
    # tell the suite-wide raise-on-deprecation guard (test_helper) that the
    # warnings emitted here -- including from spawned threads -- are expected.
    SnapDiff.silence_deprecations = false
    SnapDiffDeprecationGuard.expected = true
  end

  def teardown
    SnapDiffDeprecationGuard.expected = false
    SnapDiff::Deprecation.reset!
    SnapDiff.silence_deprecations = @original_silence

    if @original_env.nil?
      ENV.delete("SNAP_DIFF_SILENCE_DEPRECATIONS")
    else
      ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = @original_env
    end
  end

  # Emission channel under test: Kernel#warn delegates to Warning.warn
  # (Ruby >= 2.4), whose default implementation writes to $stderr. Capturing
  # $stderr via minitest's capture_io exercises that exact path -- the same
  # one a caller who has customized Warning.warn (e.g. to raise on warnings,
  # or RSpec/Rails deprecation collectors) would also observe -- without us
  # having to monkey-patch Warning ourselves just to assert on it.
  def capture_warnings
    _out, err = capture_io { yield }
    err.lines.reject(&:empty?)
  end

  test "warns exactly once for repeated calls with the same subject" do
    lines = capture_warnings do
      3.times { SnapDiff::Deprecation.warn("Old::Thing", "New::Thing") }
    end

    assert_equal 1, lines.size
    assert_match(/\[snap_diff deprecation\]/, lines.first)
    assert_match(/Old::Thing/, lines.first)
    assert_match(/New::Thing/, lines.first)
  end

  # Actionable attribution: the first caller frame OUTSIDE the gem's lib
  # dir is named, so users can find the deprecated reference. This test
  # file plays the part of "user code" -- the warning must point here.
  test "warning names the caller's file and line" do
    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Where", "New::Where")
    end

    assert_match(/called from #{Regexp.escape(File.expand_path(__FILE__))}:\d+/, lines.first)
  end

  test "warns separately for different subjects" do
    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::A", "New::A")
      SnapDiff::Deprecation.warn("Old::B", "New::B")
    end

    assert_equal 2, lines.size
  end

  test "silenced via SnapDiff.silence_deprecations accessor" do
    SnapDiff.silence_deprecations = true

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing")
    end

    assert_empty lines
  end

  test "not silenced when accessor is explicitly false" do
    SnapDiff.silence_deprecations = false

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing")
    end

    assert_equal 1, lines.size
  end

  test "silenced via SNAP_DIFF_SILENCE_DEPRECATIONS=1 env var" do
    ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "1"

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing")
    end

    assert_empty lines
  end

  test "silenced via SNAP_DIFF_SILENCE_DEPRECATIONS=true env var" do
    ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "true"

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing")
    end

    assert_empty lines
  end

  test "thread-safe: N threads warning about the same subject emit exactly once" do
    lines = capture_warnings do
      threads = Array.new(20) do
        Thread.new { SnapDiff::Deprecation.warn("Old::Racy", "New::Racy") }
      end
      threads.each(&:join)
    end

    assert_equal 1, lines.size
  end

  test "reset! clears the seen-set so a subject warns again" do
    capture_warnings { SnapDiff::Deprecation.warn("Old::Thing", "New::Thing") }

    SnapDiff::Deprecation.reset!

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing")
    end

    assert_equal 1, lines.size
  end

  # --- the once-per-process migration notice ---
  #
  # Most of the v1 surface cannot warn per use: the legacy config accessors
  # are plain delegators, and the eagerly-aliased constants (Os, the error
  # classes, VERSION) never reach const_missing. Exercising all 14 legacy
  # APIs a real setup file touches under -w produced ZERO warnings, so a 2.x
  # app was completely silent right up to the bare NameError it would get on
  # 3.0. {MIGRATION_NOTICE} is the one line that closes that gap; these
  # probes run in subprocesses because "once per process" is the contract.

  NOTICE_MARKER = "shown once per process"

  # Every door into the v1 surface that CAN be hooked, each on its own so a
  # regression in one is not masked by another still firing. (The eagerly
  # aliased constants -- Os, the error classes, VERSION -- are deliberately
  # absent: they never reach const_missing, which is exactly why the notice
  # has to exist and why UPGRADING.md documents them as silent by design.)
  LEGACY_DOORS = {
    "config delegator (write)" => "Capybara::Screenshot.window_size = [80, 80]",
    "config delegator (read)" => "Capybara::Screenshot::Diff.tolerance",
    "const_missing constant" => "Capybara::Screenshot::Diff::ImageCompare",
    "legacy include" => "Class.new { include Capybara::Screenshot::Diff }",
    # Hand-written forwarder, not one of the generated delegators above, so
    # it needs its own Deprecation.notice and its own row here.
    "hand-written derived reader" => "Capybara::Screenshot::Diff.default_options"
  }.freeze

  LEGACY_USE = LEGACY_DOORS.values.join("\n")

  LEGACY_DOORS.each do |door, code|
    test "the migration notice fires for the #{door}, on its own" do
      out = run_probe(<<~RUBY)
        require "capybara_screenshot_diff"
        3.times { #{code} }
      RUBY

      assert_equal 1, out.scan(NOTICE_MARKER).size, "expected exactly one migration notice, got:\n#{out}"
    end
  end

  # --- the require doors ------------------------------------------------
  #
  # THE beta3 HOLE. Every door above needs the user to CALL something. A v1
  # suite that requires a v1 entry point and then only calls `screenshot`
  # touches no config delegator, no const_missing and no legacy include --
  # so beta3 shipped with docs describing three warning channels and a
  # v1-only app producing zero output. Requiring a v1-NAMED file is itself
  # use of the v1 API, and is the one door every such app goes through.
  #
  # capybara_screenshot_diff/cucumber is absent for the same reason as in
  # legacy_entry_point_probe_test: it calls World(...) at load.
  V1_REQUIRE_DOORS = %w[
    capybara/screenshot/diff
    capybara-screenshot-diff
    capybara_screenshot_diff
    capybara_screenshot_diff/dsl
    capybara_screenshot_diff/minitest
    capybara_screenshot_diff/rspec
  ].freeze

  V1_REQUIRE_DOORS.each do |entry|
    test "the migration notice fires for `require #{entry.inspect}` alone" do
      out = run_probe(%(require #{entry.inspect}))

      assert_equal 1, out.scan(NOTICE_MARKER).size, "expected exactly one migration notice, got:\n#{out}"
    end
  end

  # The mirror image, and the reason the doors above cannot simply be "the
  # v1 files got loaded": the canonical gem-name entry point loads the whole
  # v1 umbrella itself, so a `gem "snap_diff-capybara"` user would eat a
  # notice about an API they never touched.
  CANONICAL_REQUIRE_DOORS = %w[
    snap_diff
    snap_diff-capybara
    snap_diff/dsl
    snap_diff/integrations/minitest
  ].freeze

  CANONICAL_REQUIRE_DOORS.each do |entry|
    test "`require #{entry.inspect}` alone stays silent" do
      out = run_probe(%(require #{entry.inspect}))

      assert_equal "", out.strip, "canonical entry points must not warn"
    end
  end

  test "the migration notice fires exactly once per process, however many legacy APIs are used" do
    out = run_probe(<<~RUBY)
      require "capybara_screenshot_diff"
      3.times do
      #{LEGACY_USE}
      end
    RUBY

    assert_equal 1, out.scan(NOTICE_MARKER).size, "expected exactly one migration notice, got:\n#{out}"
    assert_includes out, "docs/UPGRADING.md"
    assert_includes out, "still works in 2.0 and is REMOVED in 2.1"
    assert_includes out, "SNAP_DIFF_SILENCE_DEPRECATIONS"
  end

  test "the migration notice does not fire for a purely canonical setup" do
    out = run_probe(<<~RUBY)
      require "snap_diff/integrations/minitest"
      SnapDiff.configure { |c| c.window_size = [80, 80] }
      SnapDiff.config.tolerance
      SnapDiff::Comparison
      SnapDiff::Os
    RUBY

    assert_equal "", out.strip, "canonical-only usage must stay silent"
  end

  # The accessor silences everything from the moment it is set -- which is
  # necessarily AFTER the entry point that loaded SnapDiff in the first
  # place. Setting it needs the constant, and the constant needs a require.
  test "the migration notice is silenced by the SnapDiff.silence_deprecations accessor" do
    out = run_probe(<<~RUBY)
      require "snap_diff/deprecation"
      SnapDiff.silence_deprecations = true
      require "capybara_screenshot_diff"
      #{LEGACY_USE}
    RUBY

    assert_equal "", out.strip
  end

  # ...which is why the env var is the channel UPGRADING.md points a
  # Bundler.require user at: with `gem "capybara-screenshot-diff"` in the
  # Gemfile, the v1 entry point loads before any line of their code runs,
  # so the accessor has no moment early enough to cover it.
  test "the accessor cannot silence the require-time notice, and the env var can" do
    late = run_probe(<<~RUBY)
      require "capybara_screenshot_diff"
      SnapDiff.silence_deprecations = true
      #{LEGACY_USE}
    RUBY

    assert_equal 1, late.scan(NOTICE_MARKER).size,
      "the require itself warns before the accessor can be set"

    early = run_probe(<<~RUBY, "SNAP_DIFF_SILENCE_DEPRECATIONS" => "1")
      require "capybara_screenshot_diff"
      SnapDiff.silence_deprecations = true
      #{LEGACY_USE}
    RUBY

    assert_equal "", early.strip
  end

  test "the migration notice is silenced by SNAP_DIFF_SILENCE_DEPRECATIONS" do
    out = run_probe(<<~RUBY, "SNAP_DIFF_SILENCE_DEPRECATIONS" => "1")
      require "capybara_screenshot_diff"
      #{LEGACY_USE}
    RUBY

    assert_equal "", out.strip
  end

  private

  # Runs +script+ in a fresh process with only lib/ on the load path and
  # returns whatever it wrote to stderr, minus warnings from other gems.
  def run_probe(script, env = {})
    project_root = File.expand_path("../..", __dir__)
    _out, err, status = Open3.capture3(
      env, RbConfig.ruby, "-Ilib", "-e", script, chdir: project_root
    )
    assert_predicate status, :success?, err
    err.lines.grep(/\[snap_diff/).join
  end
end
