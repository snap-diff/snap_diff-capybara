# frozen_string_literal: true

require "test_helper"

# The REVERSE of legacy_tree_is_alias_only_test.rb, and the other half of
# what makes 3.0 a `git rm`.
#
# That test proves the v1 trees hold no logic. This one proves the canonical
# core does not reach BACK into them -- which is the half that actually
# breaks the gem if it is wrong: as long as any file under lib/snap_diff/
# requires a `capybara/...` path or reads a `Capybara::Screenshot.*` /
# `CapybaraScreenshotDiff::*` constant, deleting lib/capybara* leaves a core
# that no longer loads.
#
# Scope: everything the 3.0 deletion KEEPS. Files that are themselves part of
# the deletion set (DELETED_IN_3_0 below) live under lib/snap_diff/ only
# because the generator for the v1 surface has to be code, and the v1 trees
# have to stay alias-only -- they are legacy by design and go with it.
#
# Comments are ignored: "ex +Capybara::Screenshot.active?+" is history, not a
# dependency. Strings are NOT ignored -- a user-facing message naming a
# legacy accessor is a legacy reference that survives the deletion and starts
# lying the day it happens.
class CoreTreeHasNoLegacyDepsTest < ActiveSupport::TestCase
  LIB = Pathname.new(__dir__).join("../../lib").expand_path

  # Deleted alongside lib/capybara* in 3.0: these files exist to BUILD the
  # v1 compatibility surface (const_missing shims, the legacy config
  # accessor generator, the deprecation channel that announces both).
  DELETED_IN_3_0 = %w[
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
  ].freeze

  CORE_FILES = (
    [LIB.join("snap_diff.rb")] + Dir[LIB.join("snap_diff/**/*.rb")].map { |p| Pathname.new(p) }
  ).sort.reject { |file| DELETED_IN_3_0.include?(file.relative_path_from(LIB).to_s) }.freeze

  # A require of anything in the v1 trees: `capybara/screenshot/...`,
  # `capybara_screenshot_diff...`, `capybara-screenshot-diff`. Plain
  # `require "capybara"` / `"capybara/dsl"` is the base gem, not this gem's
  # legacy tree, so it must not match.
  LEGACY_REQUIRE = %r{\Arequire(_relative)?\s+["']capybara(/screenshot|_screenshot_diff|-screenshot-diff)}

  # A read or write of a v1 namespace constant.
  LEGACY_CONSTANT = /(?<![\w:])(?:::)?(?:Capybara::Screenshot|CapybaraScreenshotDiff)\b/

  # THE ALLOWLIST -- the whole point of this gate is that it shrinks.
  #
  # Keyed by path relative to lib/, valued by the EXACT offending code lines
  # that are tolerated there, each with a written reason. Line-level, not
  # file-level, on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # Seeded with every core->legacy edge that existed the day the gate was
  # written (64 of them), so the gate lands green and every later commit can
  # only take entries away. The target is an empty hash. It must never grow:
  # a new entry is a decision to keep a core->legacy edge across the 3.0
  # deletion, so it needs a written reason here AND an ADR-008 update --
  # never just a red build turned green.
  ALLOWED = {
    "snap_diff.rb" => [
      "require \"capybara/screenshot/diff/config_legacy\"",
      "require \"capybara/screenshot/diff/image_compare\"",
      "yield Capybara::Screenshot, Capybara::Screenshot::Diff"
    ],
    "snap_diff/browser_helpers.rb" => [
      "if ::Capybara::Screenshot.respond_to?(:window_size) && ::Capybara::Screenshot.window_size",
      "resize_to(::Capybara::Screenshot.window_size)"
    ],
    "snap_diff/config.rb" => [
      "add_driver_path: [Capybara::Screenshot, :add_driver_path],",
      "add_os_path: [Capybara::Screenshot, :add_os_path],",
      "blur_active_element: [Capybara::Screenshot, :blur_active_element],",
      "screenshot_enabled: [Capybara::Screenshot, :enabled],",
      "hide_caret: [Capybara::Screenshot, :hide_caret],",
      "disable_animations: [Capybara::Screenshot, :disable_animations],",
      "root: [Capybara::Screenshot, :root],",
      "stability_time_limit: [Capybara::Screenshot, :stability_time_limit],",
      "window_size: [Capybara::Screenshot, :window_size],",
      "save_path: [Capybara::Screenshot, :save_path],",
      "use_lfs: [Capybara::Screenshot, :use_lfs],",
      "screenshot_format: [Capybara::Screenshot, :screenshot_format],",
      "capybara_screenshot_options: [Capybara::Screenshot, :capybara_screenshot_options],",
      "delayed: [Capybara::Screenshot::Diff, :delayed],",
      "area_size_limit: [Capybara::Screenshot::Diff, :area_size_limit],",
      "fail_if_new: [Capybara::Screenshot::Diff, :fail_if_new],",
      "pending_if_new: [Capybara::Screenshot::Diff, :pending_if_new],",
      "fail_on_difference: [Capybara::Screenshot::Diff, :fail_on_difference],",
      "color_distance_limit: [Capybara::Screenshot::Diff, :color_distance_limit],",
      "enabled: [Capybara::Screenshot::Diff, :enabled],",
      "shift_distance_limit: [Capybara::Screenshot::Diff, :shift_distance_limit],",
      "skip_area: [Capybara::Screenshot::Diff, :skip_area],",
      "driver: [Capybara::Screenshot::Diff, :driver],",
      "tolerance: [Capybara::Screenshot::Diff, :tolerance],",
      "perceptual_threshold: [Capybara::Screenshot::Diff, :perceptual_threshold],",
      "screenshoter: [Capybara::Screenshot::Diff, :screenshoter],",
      "manager: [Capybara::Screenshot::Diff, :manager]"
    ],
    "snap_diff/dsl.rb" => [
      "require \"capybara/screenshot/diff/config_legacy\"",
      "require \"capybara/screenshot/diff/drivers\"",
      "require \"capybara/screenshot/diff/screenshot_matcher\"",
      "return false unless Capybara::Screenshot.active?",
      "delayed = options.fetch(:delayed, Capybara::Screenshot::Diff.delayed)",
      "return false unless Capybara::Screenshot.active?"
    ],
    "snap_diff/integrations/cucumber.rb" => [
      "Capybara::Screenshot::Diff.delayed = false"
    ],
    "snap_diff/reporters/html.rb" => [
      "require \"capybara/screenshot/diff/config_legacy\"",
      "root = Capybara::Screenshot.root || Pathname.pwd",
      "root / Capybara::Screenshot.save_path / \"snap_diff_report.html\""
    ],
    "snap_diff/screenshot_assertion.rb" => [
      "return unless ::Capybara::Screenshot::Diff.pending_if_new && session.new_screenshots_present?",
      "return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference",
      "return unless ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference"
    ],
    "snap_diff/screenshot_matcher.rb" => [
      "require \"capybara_screenshot_diff/snap_manager\"",
      "@driver_options = Capybara::Screenshot::Diff.default_options.merge(options)",
      "Capture::Viewport.prepare!(Capybara::Screenshot.window_size)",
      "Capture::Viewport.prepare!(Capybara::Screenshot.window_size)",
      "if Capybara::Screenshot::Diff.fail_if_new && !@snapshot.base_path.exist?",
      "To allow new screenshots: Capybara::Screenshot::Diff.fail_if_new = false",
      "Capybara::Screenshot::Diff.screenshoter.new(capture_options, comparison_options)"
    ],
    "snap_diff/screenshot_namer.rb" => [
      "@screenshot_area ||= Capybara::Screenshot.screenshot_area"
    ],
    "snap_diff/screenshoter.rb" => [
      "blurred_input = BrowserHelpers.blur_from_focused_element if Capybara::Screenshot.blur_active_element",
      "BrowserHelpers.hide_caret if Capybara::Screenshot.hide_caret",
      "BrowserHelpers.disable_animations if Capybara::Screenshot.disable_animations",
      "expected_image_width = Capybara::Screenshot.window_size[0]",
      "Os::ON_MAC && BrowserHelpers.selenium? && Capybara::Screenshot.window_size"
    ],
    "snap_diff/snap_manager.rb" => [
      "manager_class = Capybara::Screenshot::Diff.manager",
      "root = Pathname.new(Capybara::Screenshot.screenshot_area_abs)"
    ],
    "snap_diff/stable_screenshoter.rb" => [
      "@screenshoter = Capybara::Screenshot::Diff.screenshoter.new(capture_options.except(:stability_time_limit), @comparison_options)"
    ],
    "snap_diff/static.rb" => [
      "Capybara::Screenshot.root = root"
    ],
    "snap_diff/vcs.rb" => [
      "if Capybara::Screenshot.use_lfs"
    ]
  }.freeze

  test "no core file requires or references the v1 namespaces" do
    refute_empty CORE_FILES, "core glob matched nothing -- the gate would pass vacuously"

    offenders = CORE_FILES.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      The canonical core still depends on the v1 compatibility trees. Repoint
      these at their snap_diff/* equivalents (`SnapDiff.config.*`,
      `SnapDiff::Drivers.*`, `require "snap_diff/..."`) -- until they are gone,
      `git rm lib/capybara*` breaks the gem:

      #{offenders.join("\n")}
    MSG
  end

  test "the allowlist names only lines that still exist" do
    stale = ALLOWED.flat_map do |path, lines|
      present = significant_lines(LIB.join(path)).map(&:first)
      (lines - present).map { |line| "#{path}: allowlisted line no longer present: `#{line}`" }
    end

    assert_empty stale, <<~MSG
      The allowlist is out of date -- these entries protect nothing and only
      hide future regressions. Delete them:

      #{stale.join("\n")}
    MSG
  end

  private

  def offences(file)
    rel = file.relative_path_from(LIB).to_s
    allowed = ALLOWED.fetch(rel, [])

    significant_lines(file).filter_map do |line, number|
      next if allowed.include?(line)

      reason =
        if LEGACY_REQUIRE.match?(line) then "requires a v1 tree path"
        elsif LEGACY_CONSTANT.match?(line) then "references a v1 namespace constant"
        end
      "#{rel}:#{number}: #{reason} -- `#{line}`" if reason
    end
  end

  # [stripped line, 1-based line number] for every line that is not blank and
  # not a whole-line comment.
  def significant_lines(file)
    file.read.lines.each_with_index.filter_map do |line, index|
      stripped = line.strip
      [stripped, index + 1] unless stripped.empty? || stripped.start_with?("#")
    end
  end
end
