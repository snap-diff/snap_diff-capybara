# frozen_string_literal: true

require "test_helper"
require "open3"
require "snap_diff/deprecation"
require "legacy/namespace_forwarding_test" # single source of truth for the old->new MAPPING

# ADR-004 v2 step 6: resolving an old-namespace constant emits a deprecation
# warning -- exactly once per constant per process, naming the SnapDiff
# replacement, silenceable through the pre-existing SnapDiff::Deprecation
# switches (SnapDiff.silence_deprecations / SNAP_DIFF_SILENCE_DEPRECATIONS).
# Same-object identity for every pair stays pinned by
# namespace_forwarding_test.rb; this file pins only the warning behavior.
#
# LEGACY SURFACE (test/legacy/, see the Rakefile): deleted with lib/capybara*
# and snap_diff/deprecation.rb in 2.1.
class LegacyNamespaceDeprecationTest < ActiveSupport::TestCase
  # Documented exceptions that stay EAGER (real constants, never warn):
  # - Os / DSL: advertised entry-point constants, probed with
  #   Object.const_defined? by support_load_probe_test.rb -- const_defined?
  #   never triggers const_missing, so a lazy shim would break that contract.
  # - VERSION: the gemspec resolves Capybara::Screenshot::Diff::VERSION at
  #   build time; a lazy shim would make every `gem build` warn.
  EAGER_SILENT = %w[
    Capybara::Screenshot::Os
    CapybaraScreenshotDiff::DSL
    Capybara::Screenshot::Diff::VERSION
  ].freeze

  # Real constants on the shared SnapDiff::Drivers module (the Drivers alias
  # is same-object by contract), so const_missing can never fire for the leaf
  # name; resolving them through the old path still warns for ...::Drivers.
  WARNED_VIA_PARENT = %w[
    Capybara::Screenshot::Diff::Drivers::ChunkyPNGDriver
    Capybara::Screenshot::Diff::Drivers::VipsDriver
  ].freeze

  def setup
    @original_silence = SnapDiff.silence_deprecations
    # silence_deprecations? also reads the env var live, so an inherited
    # SNAP_DIFF_SILENCE_DEPRECATIONS would defeat the accessor below.
    @original_silence_env = ENV.delete("SNAP_DIFF_SILENCE_DEPRECATIONS")
    SnapDiff.silence_deprecations = false
    SnapDiff::Deprecation.reset!
    # These tests emit (and capture) the warnings on purpose; keep the
    # suite-wide raise-on-deprecation guard from test_helper out of the way.
    SnapDiffDeprecationGuard.expected = true
  end

  def teardown
    SnapDiffDeprecationGuard.expected = false
    SnapDiff.silence_deprecations = @original_silence
    ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = @original_silence_env if @original_silence_env
    SnapDiff::Deprecation.reset!
  end

  def capture_warnings
    _out, err = capture_io { yield }
    err.lines.reject(&:empty?)
  end

  NamespaceForwardingTest::MAPPING.each do |old_name, new_name|
    next if EAGER_SILENT.include?(old_name) || WARNED_VIA_PARENT.include?(old_name)

    define_method(:"test_#{old_name}_warns_once_pointing_at_#{new_name}") do
      lines = capture_warnings do
        2.times { Object.const_get(old_name) }
      end

      own_lines = lines.grep(/`#{Regexp.escape(old_name)}` is deprecated/)
      assert_equal 1, own_lines.size,
        "expected exactly one deprecation warning for #{old_name} across two resolutions, " \
        "got #{own_lines.size} in:\n#{lines.join}"
      assert_match(/#{Regexp.escape(new_name)}/, own_lines.first,
        "warning for #{old_name} should name the replacement #{new_name}")
    end
  end

  test "eager compatibility constants stay defined and silent" do
    EAGER_SILENT.each do |name|
      assert Object.const_defined?(name), "#{name} must stay an eagerly-defined constant"
    end

    lines = capture_warnings { EAGER_SILENT.each { |name| Object.const_get(name) } }

    assert_empty lines, "eager compatibility constants must not warn"
  end

  test "silencing suppresses shim warnings" do
    SnapDiff.silence_deprecations = true

    lines = capture_warnings { Object.const_get("Capybara::Screenshot::Diff::ImageCompare") }

    assert_empty lines
  end

  test "unmapped old-namespace constants still raise NameError" do
    error = assert_raises(NameError) { Capybara::Screenshot::Diff.const_get(:DoesNotExist) }
    assert_match(/DoesNotExist/, error.message)

    assert_raises(NameError) { CapybaraScreenshotDiff.const_get(:DoesNotExist) }
    assert_raises(NameError) { Capybara::Screenshot.const_get(:DoesNotExist) }
  end

  test "old constants resolve to the same objects while warning" do
    _out, _err = capture_io do
      assert_same SnapDiff::Comparison, Object.const_get("Capybara::Screenshot::Diff::ImageCompare")
      assert_same SnapDiff::SnapManager, Object.const_get("CapybaraScreenshotDiff::SnapManager")
    end
  end

  # --- subprocess probes: the gem's OWN code must never warn -------------

  PROJECT_ROOT = File.expand_path("../..", __dir__)
  FIXTURE_IMAGE = File.expand_path("../fixtures/images/a.png", __dir__)

  # Legacy entry points exercise load + a real comparison + the session
  # lifecycle; the canonical snap_diff entry exercises load + comparison +
  # config. Zero deprecation output allowed: internal code must reference
  # SnapDiff names only.
  ENTRY_POINT_PROBES = {
    "capybara_screenshot_diff" => :legacy,
    "capybara_screenshot_diff/minitest" => :legacy,
    "capybara_screenshot_diff/rspec" => :legacy,
    "capybara-screenshot-diff" => :legacy,
    "snap_diff" => :canonical
  }.freeze

  test "loading each entry point and running a trivial comparison emits no deprecation output" do
    failures = ENTRY_POINT_PROBES.filter_map do |entry, kind|
      body = "require #{entry.inspect}\n"
      # The probe itself names chunky_png (the one driver present on every
      # box, so the comparison below is deterministic), and naming it is a
      # user choice that warns about the 2.1 removal by design. Silence THAT
      # channel only -- the legacy-namespace warnings this test is actually
      # about stay live.
      body << "SnapDiff::Removal.suppress!\n"
      body << "raise \"compare failed\" unless SnapDiff.compare(#{FIXTURE_IMAGE.inspect}, #{FIXTURE_IMAGE.inspect}, driver: :chunky_png).quick_equal?\n"
      if kind == :legacy
        body << "CapybaraScreenshotDiff.assertions_present?\n"
        body << "CapybaraScreenshotDiff.pending_screenshots_message\n"
        body << "CapybaraScreenshotDiff.reset\n"
      else
        body << "SnapDiff.config\n"
      end

      _out, err, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", body, chdir: PROJECT_ROOT)

      # ADR-010: requiring a v1-named entry point is itself use of the v1
      # API and now announces itself once. That line is the ENTRY's, not
      # internal code's -- what this test is about is a per-constant warning,
      # which can only come from the gem naming an old constant internally.
      # Canonical entries stay held to zero output of any kind.
      noise = err.lines.grep(/deprecation/)
      noise = noise.grep_v(/This process uses the v1/) if kind == :legacy

      if !status.success?
        "require \"#{entry}\": probe failed:\n#{err}"
      elsif !noise.empty?
        "require \"#{entry}\": internal use emitted deprecation output:\n#{noise.join}"
      end
    end

    assert_empty failures, failures.join("\n\n")
  end

  test "touching an old constant in a fresh unsilenced process does warn (control probe)" do
    script = 'require "capybara_screenshot_diff"; Capybara::Screenshot::Diff::ImageCompare'
    _out, err, status = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", script, chdir: PROJECT_ROOT)

    assert status.success?, err
    assert_match(/\[snap_diff deprecation\].*Capybara::Screenshot::Diff::ImageCompare.*SnapDiff::Comparison/, err)
  end
end
