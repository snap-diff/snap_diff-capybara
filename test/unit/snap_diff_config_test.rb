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

  # Reflection-based completeness check, reworked for the ADR-008 storage
  # inversion (the old version derived settings from mattr class variables,
  # which no longer exist). Two directions:
  #
  # (a) every singleton writer on the legacy modules is a mapped config
  #     setting -- a future `mattr_accessor :foo` (active_support's ext is
  #     one require away) or hand-rolled writer would create unmapped
  #     storage invisible to SnapDiff.config;
  # (b) SnapDiff.config stores exactly one ivar per declared setting -- catches
  #     both an unmapped ivar sneaking into Config and a mapped setting
  #     whose ivar is missing (which would also silently escape
  #     test_helper's per-test ivar snapshot/restore).
  NON_CONFIG_WRITERS = [].freeze # currently no non-config writer API on the legacy modules

  test "every legacy singleton writer is covered by SnapDiff::LegacyShims::CONFIG_MAPPING" do
    covered = SnapDiff::LegacyShims::CONFIG_MAPPING.values

    [Capybara::Screenshot, Capybara::Screenshot::Diff].each do |mod|
      writers = mod.singleton_class.public_instance_methods(false).grep(/=\z/) - NON_CONFIG_WRITERS

      assert_operator writers.size, :>, 0, "#{mod} lost all its config writers"
      writers.each do |writer|
        mattr = writer.to_s.delete_suffix("=").to_sym

        assert_includes covered, [mod, mattr],
          "#{mod}.#{writer} is a config writer with no SnapDiff::Config mapping. " \
          "Add an entry to LegacyShims::CONFIG_MAPPING (rename the key if `#{mattr}` collides " \
          "with an existing one, as `enabled` does), or add it to NON_CONFIG_WRITERS " \
          "if it is deliberately not a config setting."
      end
    end
  end

  # The two halves of the split are only safe while they agree: Config
  # declares the settings and knows nothing about the legacy holders,
  # LegacyShims says which holder each one is exposed on. A setting in one
  # and not the other is either storage with no v1 accessor or a v1
  # accessor delegating to a setting that does not exist.
  test "LegacyShims::CONFIG_MAPPING covers exactly Config::SETTINGS" do
    assert_equal SnapDiff::Config::SETTINGS, SnapDiff::LegacyShims::CONFIG_MAPPING.keys
  end

  test "SnapDiff.config stores exactly one ivar per declared setting" do
    assert_equal SnapDiff::Config::SETTINGS.map { |k| :"@#{k}" }.sort,
      SnapDiff.config.instance_variables.sort
  end

  test "every mapped setting is readable via config and equal to its mattr_accessor's value" do
    SnapDiff::LegacyShims::CONFIG_MAPPING.each do |name, (mod, mattr)|
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
    original = SnapDiff.config.fail_if_new

    begin
      SnapDiff.config.fail_if_new = true
      assert_equal true, config.fail_if_new

      config.fail_if_new = false
      assert_equal false, SnapDiff.config.fail_if_new
    ensure
      SnapDiff.config.fail_if_new = original
    end
  end

  test "writing window_size via the old mattr_accessor is visible via config, and back" do
    original = SnapDiff.config.window_size

    begin
      SnapDiff.config.window_size = [1280, 1024]
      assert_equal [1280, 1024], config.window_size

      config.window_size = [800, 600]
      assert_equal [800, 600], SnapDiff.config.window_size
    ensure
      SnapDiff.config.window_size = original
    end
  end

  # SnapDiff.config.screenshot_enabled and SnapDiff.config.enabled are
  # two independent settings that happen to share a bare name in their own
  # modules (see SnapDiff.config.active?, which reads both). Config is
  # flat, so it cannot expose two attributes both called `enabled` -- the
  # Screenshot-side one is renamed `screenshot_enabled`. This test proves
  # the rename didn't accidentally collapse them into one shared value.
  test "screenshot_enabled and enabled stay independent settings under Config" do
    original_screenshot = SnapDiff.config.screenshot_enabled
    original_diff = SnapDiff.config.enabled

    begin
      config.screenshot_enabled = true
      config.enabled = false

      assert_equal true, SnapDiff.config.screenshot_enabled
      assert_equal false, SnapDiff.config.enabled
      assert_equal true, config.screenshot_enabled
      assert_equal false, config.enabled
    ensure
      SnapDiff.config.screenshot_enabled = original_screenshot
      SnapDiff.config.enabled = original_diff
    end
  end

  # ADR-008 step 7b moved this precedence rule from
  # SnapDiff.config.active? into Config#active?, and found it had no
  # test at all: replacing the whole expression with a bare `enabled` kept
  # all 529 unit tests green. The full truth table is pinned here, through
  # both the canonical method and the legacy forwarder, so it cannot move
  # again unnoticed.
  #
  # The rule: the Screenshot-side flag wins whenever it was set to anything
  # at all; only a nil there falls through to the Diff-side flag.
  ACTIVE_TRUTH_TABLE = [
    [true, true, true],
    [true, false, true],
    [false, true, false],
    [false, false, false],
    [nil, true, true],
    [nil, false, false]
  ].freeze

  test "active? gives Screenshot.enabled precedence and only falls through on nil" do
    original_screenshot = SnapDiff.config.screenshot_enabled
    original_diff = SnapDiff.config.enabled

    ACTIVE_TRUTH_TABLE.each do |screenshot_enabled, enabled, expected|
      config.screenshot_enabled = screenshot_enabled
      config.enabled = enabled
      context = "screenshot_enabled=#{screenshot_enabled.inspect}, enabled=#{enabled.inspect}"

      assert_equal expected, !!config.active?, "Config#active? with #{context}"
      assert_equal expected, !!SnapDiff.config.active?, "SnapDiff.config.active? with #{context}"
    end
  ensure
    SnapDiff.config.screenshot_enabled = original_screenshot
    SnapDiff.config.enabled = original_diff
  end

  test "writing root through config round-trips through the same Pathname coercion" do
    original = SnapDiff.config.root

    begin
      config.root = "/tmp"

      assert_equal Pathname("/tmp"), SnapDiff.config.root
      assert_equal Pathname("/tmp"), config.root
    ensure
      SnapDiff.config.root = original
    end
  end

  test "SnapDiff.configure yields the SnapDiff.config object" do
    yielded = nil
    SnapDiff.configure { |c| yielded = c }

    assert_same config, yielded
  end

  test "SnapDiff.configure lets callers set values through the yielded config" do
    original = SnapDiff.config.tolerance

    begin
      SnapDiff.configure { |c| c.tolerance = 0.0321 }
      assert_equal 0.0321, SnapDiff.config.tolerance
    ensure
      SnapDiff.config.tolerance = original
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
