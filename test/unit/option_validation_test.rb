# frozen_string_literal: true

require "test_helper"
require "open3"

# NO SILENT NO-OPS (ADR-010).
#
# The per-screenshot options hash was frozen but never validated, so any key
# the gem does not read -- a typo, a v1 option that no longer exists, an
# option meant for a different gem -- configured nothing and said nothing.
# A tolerance you believe is set and is not is worse than no tolerance at
# all: the suite stays green and stops testing.
#
# 2.0 warns once per unknown key; 2.1 raises ArgumentError. Guarded at
# SnapDiff::Comparison, the one funnel EVERY option hash reaches -- the DSL
# (screenshot -> ScreenshotMatcher -> Comparison) and the file-to-file
# SnapDiff.compare both end up there, so a second entry point cannot be
# added past this check by accident.
#
# Subprocess probes: "once per process" is the contract, and this suite's
# test_helper suppresses these warnings globally (it exercises the doomed
# options by design), so an in-process assertion could measure neither.
class OptionValidationTest < ActiveSupport::TestCase
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  IMAGE_A = File.join(PROJECT_ROOT, "test/fixtures/images/a.png")
  IMAGE_B = File.join(PROJECT_ROOT, "test/fixtures/images/b.png")

  test "an unrecognised option warns, naming the key and 2.1" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      #{compare(tolerence: 0.5)}
    RUBY

    unknown = lines.grep(/tolerence/)
    assert_equal 1, unknown.size, lines.join
    assert_match(/does nothing/, unknown.first)
    assert_match(/2\.1 raises/, unknown.first)
  end

  test "an unrecognised option warns once per process, not once per comparison" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { #{compare(tolerence: 0.5)} }
    RUBY

    assert_equal 1, lines.grep(/tolerence/).size, lines.join
  end

  test "each distinct unrecognised key gets its own warning" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      #{compare(tolerence: 0.5, colour_distance_limit: 3)}
    RUBY

    assert_equal 1, lines.grep(/tolerence/).size, lines.join
    assert_equal 1, lines.grep(/colour_distance_limit/).size, lines.join
  end

  # The v1 option people most often still have in a setup file. It is not a
  # "typo" at all -- it was real once -- which is exactly why an unknown-key
  # check has to cover the general case rather than a blocklist.
  test "a per-screenshot option through the DSL is validated too" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      SnapDiff::Comparison.new(
        #{IMAGE_A.inspect}, #{IMAGE_B.inspect},
        SnapDiff.config.default_options.merge(shift_distance_limits: 3)
      )
    RUBY

    assert_equal 1, lines.grep(/shift_distance_limits/).size, lines.join
  end

  # The half that decides whether anyone will listen: config.default_options
  # merges a dozen keys into EVERY comparison, and the matcher adds more on
  # its way through. If any of those tripped the check, the warning would be
  # unconditional noise and users would filter the channel out entirely.
  test "a fully-specified real comparison produces no unknown-option warning" do
    out = probe_stderr(<<~RUBY)
      require "snap_diff"
      #{compare(
        tolerance: 0.01,
        color_distance_limit: 8,
        area_size_limit: 100,
        perceptual_threshold: 2,
        median_filter_window_size: 3,
        skip_area: nil,
        crop: nil,
        delayed: false,
        screenshot_format: "png",
        capybara_screenshot_options: {}
      )}
    RUBY

    assert_empty out.lines.grep(/not a recognised/), "recognised options must not warn"
  end

  test "silenced by SNAP_DIFF_SILENCE_DEPRECATIONS" do
    out = probe_stderr(<<~RUBY, "SNAP_DIFF_SILENCE_DEPRECATIONS" => "1")
      require "snap_diff"
      #{compare(tolerence: 0.5)}
    RUBY

    assert_equal "", out
  end

  private

  def compare(**options)
    args = [IMAGE_A.inspect, IMAGE_B.inspect]
    options.each { |key, value| args << "#{key}: #{value.inspect}" }
    "SnapDiff.compare(#{args.join(", ")})"
  end

  def probe(script, env = {})
    probe_stderr(script, env).lines.reject { |line| line.strip.empty? }
  end

  def probe_stderr(script, env = {})
    _out, err, status = Open3.capture3(
      env, RbConfig.ruby, "-Ilib", "-e", script, chdir: PROJECT_ROOT
    )
    assert_predicate status, :success?, err
    err.lines.grep(/\[snap_diff/).join
  end
end
