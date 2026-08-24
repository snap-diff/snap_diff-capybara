# frozen_string_literal: true

require "test_helper"

# The Config-only half. Everything about the v1 mattr_accessor VIEW of this
# same storage -- LegacyShims::CONFIG_MAPPING's completeness and the
# write-through-either-surface round trips -- lives in
# test/legacy/legacy_config_accessors_test.rb and is deleted with the v1
# trees in 2.1. What is here has to keep standing on its own after that.
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

  # Catches both an unmapped ivar sneaking into Config and a declared
  # setting whose ivar is missing (which would also silently escape
  # test_helper's per-test ivar snapshot/restore).
  test "SnapDiff.config stores exactly one ivar per declared setting" do
    assert_equal SnapDiff::Config::SETTINGS.map { |k| :"@#{k}" }.sort,
      SnapDiff.config.instance_variables.sort
  end

  # screenshot_enabled and enabled are two independent settings that
  # happened to share a bare name in their own v1 modules (see #active?,
  # which reads both). Config is flat, so it cannot expose two attributes
  # both called `enabled` -- the Screenshot-side one is renamed
  # `screenshot_enabled`. This proves the rename didn't accidentally
  # collapse them into one shared value.
  test "screenshot_enabled and enabled stay independent settings under Config" do
    original_screenshot = config.screenshot_enabled
    original_diff = config.enabled

    begin
      config.screenshot_enabled = true
      config.enabled = false

      assert_equal true, config.screenshot_enabled
      assert_equal false, config.enabled

      config.screenshot_enabled = false
      config.enabled = true

      assert_equal false, config.screenshot_enabled
      assert_equal true, config.enabled
    ensure
      config.screenshot_enabled = original_screenshot
      config.enabled = original_diff
    end
  end

  # ADR-008 step 7b moved this precedence rule into Config#active?, and
  # found it had no test at all: replacing the whole expression with a bare
  # `enabled` kept all 529 unit tests green.
  #
  # The rule: the screenshot-side flag wins whenever it was set to anything
  # at all; only a nil there falls through to the diff-side flag.
  ACTIVE_TRUTH_TABLE = [
    [true, true, true],
    [true, false, true],
    [false, true, false],
    [false, false, false],
    [nil, true, true],
    [nil, false, false]
  ].freeze

  test "active? gives screenshot_enabled precedence and only falls through on nil" do
    original_screenshot = config.screenshot_enabled
    original_diff = config.enabled

    ACTIVE_TRUTH_TABLE.each do |screenshot_enabled, enabled, expected|
      config.screenshot_enabled = screenshot_enabled
      config.enabled = enabled
      context = "screenshot_enabled=#{screenshot_enabled.inspect}, enabled=#{enabled.inspect}"

      assert_equal expected, !!config.active?, "Config#active? with #{context}"
    end
  ensure
    config.screenshot_enabled = original_screenshot
    config.enabled = original_diff
  end

  # The two path-segment flags were only ever exercised TOGETHER (both true
  # in test/system_test_case.rb and the rspec fixtures, both nil everywhere
  # else), so either `if` could be deleted or swapped for the other flag and
  # the whole suite stayed green. All four combinations, with the segment
  # sources stubbed so the assertion names the expected path literally
  # rather than recomputing it.
  SCREENSHOT_AREA_COMBINATIONS = [
    [nil, nil, "doc/screenshots"],
    [true, nil, "doc/screenshots/fake_os"],
    [nil, true, "doc/screenshots/fake_driver"],
    [true, true, "doc/screenshots/fake_os/fake_driver"]
  ].freeze

  test "screenshot_area appends the os and driver segments independently" do
    original_os, original_driver, original_save_path =
      config.add_os_path, config.add_driver_path, config.save_path

    SnapDiff::Os.stub(:name, "fake_os") do
      Capybara.stub(:current_driver, :fake_driver) do
        config.save_path = "doc/screenshots"

        SCREENSHOT_AREA_COMBINATIONS.each do |add_os_path, add_driver_path, expected|
          config.add_os_path = add_os_path
          config.add_driver_path = add_driver_path

          assert_equal expected, config.screenshot_area,
            "screenshot_area with add_os_path=#{add_os_path.inspect}, " \
            "add_driver_path=#{add_driver_path.inspect}"
        end
      end
    end
  ensure
    config.add_os_path = original_os
    config.add_driver_path = original_driver
    config.save_path = original_save_path
  end

  # The vips tolerance floor in Config#default_options is the one literal in
  # there that is not a stored setting, and deleting it left the full suite
  # green (config.rb's then-arm had a hit count of 0): nothing ever asked for
  # default_options with driver == :vips and no explicit tolerance.
  test "default_options floors tolerance at 0.001 for vips and only for vips" do
    original_driver, original_tolerance = config.driver, config.tolerance

    begin
      config.tolerance = nil

      config.driver = :vips
      assert_equal 0.001, config.default_options[:tolerance]

      config.driver = :chunky_png
      assert_nil config.default_options[:tolerance]

      # An explicit tolerance still wins over the floor.
      config.tolerance = 0.5
      config.driver = :vips
      assert_equal 0.5, config.default_options[:tolerance]
    ensure
      config.driver = original_driver
      config.tolerance = original_tolerance
    end
  end

  test "writing root through config round-trips through the same Pathname coercion" do
    original = config.root

    begin
      config.root = "/tmp"

      assert_equal Pathname("/tmp"), config.root
    ensure
      config.root = original
    end
  end

  # --- fail_if_new precedence ------------------------------------------
  #
  # NOT about what the default IS: failing only under CI stays, deliberately
  # (a locally recorded baseline is often worthless across OS). This is only
  # about who wins. An explicit setting outranks the environment sniff --
  # the ordering insta narrowed to in insta#924 after Ruff hit it ("normally,
  # CLI flags take precedence over environment variables"), and the one Jest
  # got backwards for a whole major version in jest#12288, where reading
  # argv.ci instead of detected CI state made `CI=1 jest` and `jest --ci`
  # disagree.
  #
  # For "explicit wins" to mean anything the fallback has to be live: while
  # the CI sniff was frozen into the ivar at require time there was no way to
  # tell "the user asked for false" from "CI was absent when we loaded".
  def with_env_ci(value)
    original = ENV["CI"]
    ENV["CI"] = value
    yield
  ensure
    ENV["CI"] = original
  end

  test "an unset fail_if_new reads ENV['CI'] live, not once at require time" do
    config.fail_if_new = nil

    with_env_ci(nil) { assert_equal false, config.fail_if_new }
    with_env_ci("") { assert_equal false, config.fail_if_new, "an empty CI is not CI" }
    with_env_ci("true") { assert_equal true, config.fail_if_new }
  end

  test "an explicit fail_if_new outranks ENV['CI'] in both directions" do
    config.fail_if_new = false
    with_env_ci("true") { assert_equal false, config.fail_if_new, "the user said false under CI=true" }

    config.fail_if_new = true
    with_env_ci(nil) { assert_equal true, config.fail_if_new, "the user said true off CI" }

    config.fail_if_new = nil
    with_env_ci("true") { assert_equal true, config.fail_if_new, "nil hands it back to the environment" }
  end

  test "SnapDiff.configure yields the SnapDiff.config object" do
    yielded = nil
    SnapDiff.configure { |c| yielded = c }

    assert_same config, yielded
  end

  test "SnapDiff.configure lets callers set values through the yielded config" do
    original = config.tolerance

    begin
      SnapDiff.configure { |c| c.tolerance = 0.0321 }
      assert_equal 0.0321, config.tolerance
    ensure
      config.tolerance = original
    end
  end
end
