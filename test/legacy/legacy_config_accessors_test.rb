# frozen_string_literal: true

require "test_helper"
# The shared harness loads canonical entry points only, so a legacy-surface
# test pulls in the v1 entry itself -- the require goes with the file in 2.1.
require "capybara_screenshot_diff"

# LEGACY SURFACE (test/legacy/, see the Rakefile).
#
# The v1 half of snap_diff_config_test.rb: SnapDiff::LegacyShims generates
# the old Capybara::Screenshot / Capybara::Screenshot::Diff mattr_accessors
# as a second VIEW of the one SnapDiff::Config storage. Everything here is
# about that view -- the mapping's completeness, and that a write through
# either surface is visible from the other. Verbatim from the canonical
# file, which keeps the Config-only half; both go on passing until 3.0
# deletes legacy_shims.rb, this file, and the trees they serve.
class LegacyConfigAccessorsTest < ActiveSupport::TestCase
  def config
    SnapDiff.config
  end

  # Reflection-based completeness check, reworked for the ADR-008 storage
  # inversion (the old version derived settings from mattr class variables,
  # which no longer exist). Two directions:
  #
  # (a) every singleton writer on the legacy modules is a mapped config
  #     setting -- a future `mattr_accessor :foo` (active_support's ext is
  #     one require away) or hand-rolled writer would create unmapped
  #     storage invisible to SnapDiff.config;
  # (b) SnapDiff.config stores exactly one ivar per declared setting (that
  #     half stays in the canonical file: Config outlives the mapping).
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

  # ADR-008 step 7b moved this precedence rule from
  # Capybara::Screenshot.active? into Config#active?, and found it had no
  # test at all: replacing the whole expression with a bare `enabled` kept
  # all 529 unit tests green. The full truth table is pinned here, through
  # both the canonical method and the legacy forwarder, so it cannot move
  # again unnoticed. (The canonical file pins the Config#active? column on
  # its own, so the rule survives this file's deletion.)
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
    original_screenshot = Capybara::Screenshot.enabled
    original_diff = Capybara::Screenshot::Diff.enabled

    ACTIVE_TRUTH_TABLE.each do |screenshot_enabled, enabled, expected|
      config.screenshot_enabled = screenshot_enabled
      config.enabled = enabled
      context = "screenshot_enabled=#{screenshot_enabled.inspect}, enabled=#{enabled.inspect}"

      assert_equal expected, !!config.active?, "Config#active? with #{context}"
      assert_equal expected, !!Capybara::Screenshot.active?, "Capybara::Screenshot.active? with #{context}"
    end
  ensure
    Capybara::Screenshot.enabled = original_screenshot
    Capybara::Screenshot::Diff.enabled = original_diff
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
