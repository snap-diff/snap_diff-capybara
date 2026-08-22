# frozen_string_literal: true

require "test_helper"

class SnapDiffConfigTest < ActiveSupport::TestCase
  def config
    SnapDiff.config
  end

  test "SnapDiff.config returns a SnapDiff::Config" do
    assert_kind_of SnapDiff::Config, config
  end

  test "SnapDiff.config memoizes the same instance across calls" do
    assert_same config, SnapDiff.config
  end

  # Reflection-based completeness check: derive the real, current list of
  # mattr_accessor/mattr_reader settings straight from the class variables
  # Rails' mattr_* declares them as (one @@foo per setting), rather than a
  # hand-maintained list here. If someone adds a new mattr_accessor to
  # Capybara::Screenshot or Capybara::Screenshot::Diff without adding a
  # matching entry to SnapDiff::Config::MAPPING, this test fails -- the
  # count is derived, not asserted as a literal number.
  test "SnapDiff::Config::MAPPING covers every current mattr_accessor setting" do
    covered = SnapDiff::Config::MAPPING.values

    [Capybara::Screenshot, Capybara::Screenshot::Diff].each do |mod|
      mod.class_variables.each do |cv|
        mattr = cv.to_s.delete_prefix("@@").to_sym

        assert_includes covered, [mod, mattr],
          "#{mod}.#{mattr} is a mattr_accessor with no SnapDiff::Config mapping. " \
          "Add an entry to Config::MAPPING (rename the key if `#{mattr}` collides " \
          "with an existing one, as `enabled` does)."
      end
    end
  end

  test "every mapped setting is readable via config and equal to its mattr_accessor's value" do
    SnapDiff::Config::MAPPING.each do |name, (mod, mattr)|
      expected = mod.public_send(mattr)
      actual = config.public_send(name)

      if expected.nil?
        assert_nil actual, "config.#{name} should equal #{mod}.#{mattr}"
      else
        assert_equal expected, actual, "config.#{name} should equal #{mod}.#{mattr}"
      end
    end
  end

  test "writing fail_if_new via the old mattr_accessor is visible via config, and back" do
    original = Capybara::Screenshot::Diff.fail_if_new

    begin
      Capybara::Screenshot::Diff.fail_if_new = true
      assert_equal true, config.fail_if_new

      config.fail_if_new = false
      assert_equal false, Capybara::Screenshot::Diff.fail_if_new
    ensure
      Capybara::Screenshot::Diff.fail_if_new = original
    end
  end

  test "writing window_size via the old mattr_accessor is visible via config, and back" do
    original = Capybara::Screenshot.window_size

    begin
      Capybara::Screenshot.window_size = [1280, 1024]
      assert_equal [1280, 1024], config.window_size

      config.window_size = [800, 600]
      assert_equal [800, 600], Capybara::Screenshot.window_size
    ensure
      Capybara::Screenshot.window_size = original
    end
  end

  # Capybara::Screenshot.enabled and Capybara::Screenshot::Diff.enabled are
  # two independent settings that happen to share a bare name in their own
  # modules (see Capybara::Screenshot.active?, which reads both). Config is
  # flat, so it cannot expose two attributes both called `enabled` -- the
  # Screenshot-side one is renamed `screenshot_enabled`. This test proves
  # the rename didn't accidentally collapse them into one shared value.
  test "screenshot_enabled and enabled stay independent settings under Config" do
    original_screenshot = Capybara::Screenshot.enabled
    original_diff = Capybara::Screenshot::Diff.enabled

    begin
      config.screenshot_enabled = true
      config.enabled = false

      assert_equal true, Capybara::Screenshot.enabled
      assert_equal false, Capybara::Screenshot::Diff.enabled
      assert_equal true, config.screenshot_enabled
      assert_equal false, config.enabled
    ensure
      Capybara::Screenshot.enabled = original_screenshot
      Capybara::Screenshot::Diff.enabled = original_diff
    end
  end

  test "writing root through config round-trips through the same Pathname coercion" do
    original = Capybara::Screenshot.root

    begin
      config.root = "/tmp"

      assert_equal Pathname("/tmp"), Capybara::Screenshot.root
      assert_equal Pathname("/tmp"), config.root
    ensure
      Capybara::Screenshot.root = original
    end
  end

  test "SnapDiff.configure yields the SnapDiff.config object" do
    yielded = nil
    SnapDiff.configure { |c| yielded = c }

    assert_same config, yielded
  end

  test "SnapDiff.configure lets callers set values through the yielded config" do
    original = Capybara::Screenshot::Diff.tolerance

    begin
      SnapDiff.configure { |c| c.tolerance = 0.0321 }
      assert_equal 0.0321, Capybara::Screenshot::Diff.tolerance
    ensure
      Capybara::Screenshot::Diff.tolerance = original
    end
  end

  test "SnapDiff.start (v1-style two-arg yield) and SnapDiff.configure (single Config yield) coexist" do
    diff_yielded = []
    SnapDiff.start { |screenshot, diff| diff_yielded << [screenshot, diff] }
    assert_equal [[Capybara::Screenshot, Capybara::Screenshot::Diff]], diff_yielded

    config_yielded = []
    SnapDiff.configure { |c| config_yielded << c }
    assert_equal [config], config_yielded
  end
end
