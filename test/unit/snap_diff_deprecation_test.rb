# frozen_string_literal: true

require "test_helper"
require "snap_diff/deprecation"

class SnapDiffDeprecationTest < ActiveSupport::TestCase
  def setup
    SnapDiff::Deprecation.reset!
    @original_silence = SnapDiff.silence_deprecations
    @original_env = ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"]
  end

  def teardown
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
      3.times { SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant) }
    end

    assert_equal 1, lines.size
    assert_match(/\[snap_diff deprecation\]/, lines.first)
    assert_match(/Old::Thing/, lines.first)
    assert_match(/New::Thing/, lines.first)
  end

  test "warns separately for different subjects" do
    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::A", "New::A", category: :constant)
      SnapDiff::Deprecation.warn("Old::B", "New::B", category: :constant)
    end

    assert_equal 2, lines.size
  end

  test "silenced via SnapDiff.silence_deprecations accessor" do
    SnapDiff.silence_deprecations = true

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant)
    end

    assert_empty lines
  end

  test "not silenced when accessor is explicitly false" do
    SnapDiff.silence_deprecations = false

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant)
    end

    assert_equal 1, lines.size
  end

  test "silenced via SNAP_DIFF_SILENCE_DEPRECATIONS=1 env var" do
    ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "1"

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant)
    end

    assert_empty lines
  end

  test "silenced via SNAP_DIFF_SILENCE_DEPRECATIONS=true env var" do
    ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"] = "true"

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant)
    end

    assert_empty lines
  end

  test "thread-safe: N threads warning about the same subject emit exactly once" do
    lines = capture_warnings do
      threads = Array.new(20) do
        Thread.new { SnapDiff::Deprecation.warn("Old::Racy", "New::Racy", category: :constant) }
      end
      threads.each(&:join)
    end

    assert_equal 1, lines.size
  end

  test "reset! clears the seen-set so a subject warns again" do
    capture_warnings { SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant) }

    SnapDiff::Deprecation.reset!

    lines = capture_warnings do
      SnapDiff::Deprecation.warn("Old::Thing", "New::Thing", category: :constant)
    end

    assert_equal 1, lines.size
  end
end
