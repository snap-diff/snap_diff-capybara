# frozen_string_literal: true

require "test_helper"
require "open3"

class SnapDiffTest < ActiveSupport::TestCase
  # Deliberate legacy-name use: this test pins the public alias claim in its
  # own name, so it silences the shim warning locally (the suite-wide guard
  # in test_helper raises on unexpected ones).
  test "SnapDiff::Comparison aliases Capybara::Screenshot::Diff::ImageCompare" do
    original_silence = SnapDiff.silence_deprecations
    SnapDiff.silence_deprecations = true

    assert_same Capybara::Screenshot::Diff::ImageCompare, SnapDiff::Comparison
  ensure
    SnapDiff.silence_deprecations = original_silence
  end

  test ".compare returns the same kind of result as Diff.compare, forwarding options" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png",
      tolerance: 0.02
    )

    assert_kind_of SnapDiff::Comparison, result
    assert_equal 0.02, result.driver_options[:tolerance]
  end

  # Regression test for a load-order bug: `require "snap_diff"` standalone
  # (nothing else preloaded) used to raise
  # `NameError: uninitialized constant ...ImageCompare::Drivers` because
  # image_compare.rb called Drivers.for without requiring drivers.rb.
  # test_helper.rb preloads the whole gem, so only a subprocess with a
  # fresh load path can catch this class of bug.
  test "require \"snap_diff\" is standalone-loadable in a fresh process" do
    script = <<~RUBY
      require "snap_diff"
      result = SnapDiff.compare(#{(TEST_IMAGES_DIR / "a.png").to_s.inspect}, #{(TEST_IMAGES_DIR / "b.png").to_s.inspect})
      exit(result.is_a?(SnapDiff::Comparison) ? 0 : 1)
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "expected standalone `require \"snap_diff\"` to succeed, got:\n#{out}"
  end

  # Regression test (#218 adversarial review): the probe above only builds a
  # comparison; annotation runs when a difference is actually reported, and
  # under bare `require "snap_diff"` that used to raise
  # `NameError: uninitialized constant CapybaraScreenshotDiff::RED_RGBA` --
  # the annotation colors were defined only in the umbrella
  # capybara_screenshot_diff.rb, which this entry never loads.
  test "bare require \"snap_diff\" can annotate a difference between differing images" do
    script = <<~RUBY
      require "snap_diff"
      require "fileutils"
      require "tmpdir"

      Dir.mktmpdir do |dir|
        base = File.join(dir, "base.png")
        new_image = File.join(dir, "new.png")
        FileUtils.cp(#{(TEST_IMAGES_DIR / "a.png").to_s.inspect}, base)
        FileUtils.cp(#{(TEST_IMAGES_DIR / "b.png").to_s.inspect}, new_image)

        comparison = SnapDiff.compare(base, new_image)
        abort("expected a.png and b.png to differ") unless comparison.different?
        comparison.error_message
      end
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "expected bare `require \"snap_diff\"` to annotate a difference, got:\n#{out}"
  end

  # Acyclicity contract (the #208 deadlock-class fix): the lean
  # `require "snap_diff"` entry must NEVER pull the umbrella
  # capybara_screenshot_diff.rb back in. The old autoload wiring had
  # snap_diff <-> capybara_screenshot_diff requiring each other, which
  # produced load-order deadlocks/partially-initialized constants; #208
  # broke the cycle, but until now only discipline guarded it -- a probe
  # that reintroduced the cycle left the whole suite green. This asserts
  # the contract as data: after a bare require, the umbrella file must be
  # absent from $LOADED_FEATURES.
  test "bare require \"snap_diff\" never loads the umbrella capybara_screenshot_diff" do
    script = <<~RUBY
      require "snap_diff"
      umbrella = $LOADED_FEATURES.grep(%r{/lib/capybara_screenshot_diff\\.rb\\z})
      abort("umbrella loaded via: \#{umbrella.join(", ")}") unless umbrella.empty?
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script)

    assert status.success?, "expected bare `require \"snap_diff\"` to keep the umbrella unloaded, got:\n#{out}"
  end

  # Dual-install guard: both gem names ship identical files, so with BOTH
  # activated every require silently resolves from whichever gem activated
  # first -- version skew between them is undetectable. The entry point
  # refuses that setup outright.
  test "raises when both capybara-screenshot-diff and snap_diff-capybara are activated" do
    specs = {"capybara-screenshot-diff" => :spec, "snap_diff-capybara" => :spec}

    error = assert_raises(SnapDiff::DualInstallError) { SnapDiff.assert_single_gem!(specs) }

    assert_match(/capybara-screenshot-diff/, error.message)
    assert_match(/snap_diff-capybara/, error.message)
    assert_match(/remove one/i, error.message)
  end

  test "dual-install guard passes single-gem installs and local dev from source" do
    SnapDiff.assert_single_gem!({"capybara-screenshot-diff" => :spec})
    SnapDiff.assert_single_gem!({"snap_diff-capybara" => :spec})
    SnapDiff.assert_single_gem!({}) # local dev from source: neither spec loaded
  end

  test ".start yields the same objects Diff.configure yields" do
    yielded = []
    Capybara::Screenshot::Diff.configure { |screenshot, diff| yielded << [screenshot, diff] }

    started = []
    SnapDiff.start { |screenshot, diff| started << [screenshot, diff] }

    assert_equal yielded, started
  end

  test ".start applies a setting like Diff.configure does" do
    original = Capybara::Screenshot::Diff.tolerance

    begin
      SnapDiff.start { |_screenshot, diff| diff.tolerance = 0.0123 }

      assert_equal 0.0123, Capybara::Screenshot::Diff.tolerance
    ensure
      Capybara::Screenshot::Diff.tolerance = original
    end
  end
end
