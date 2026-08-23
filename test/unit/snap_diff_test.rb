# frozen_string_literal: true

require "test_helper"
require "open3"

class SnapDiffTest < ActiveSupport::TestCase
  # The ImageCompare alias claim and the v1-shaped SnapDiff.start / .configure
  # pair live in test/legacy/legacy_forwarders_test.rb -- both are v1 surface
  # and go with it in 3.0.
  test ".compare returns the same kind of result as Diff.compare, forwarding options" do
    result = SnapDiff.compare(
      TEST_IMAGES_DIR / "a.png",
      TEST_IMAGES_DIR / "b.png",
      tolerance: 0.02
    )

    assert_kind_of SnapDiff::Comparison, result
    assert_equal 0.02, result.driver_options[:tolerance]
  end

  # The test above only pins that an EXPLICIT option round-trips, so
  # dropping `config.default_options.merge` from .compare entirely left the
  # full suite green -- callers who configure once and then call .compare
  # with no options silently lost every configured default.
  test ".compare with no options still carries the configured defaults" do
    original = SnapDiff.config.tolerance

    begin
      SnapDiff.config.tolerance = 0.0123

      result = SnapDiff.compare(TEST_IMAGES_DIR / "a.png", TEST_IMAGES_DIR / "b.png")

      assert_equal 0.0123, result.driver_options[:tolerance]
    ensure
      SnapDiff.config.tolerance = original
    end
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
  # `NameError: uninitialized constant SnapDiff::RED_RGBA` --
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

  # The acyclicity contract ("bare require never loads the umbrella") is in
  # test/legacy/legacy_forwarders_test.rb: its subject is the v1 umbrella
  # file, and once 3.0 deletes lib/capybara_screenshot_diff.rb the
  # $LOADED_FEATURES grep is empty by construction, so the guard could never
  # fail again.

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
end
