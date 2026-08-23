# frozen_string_literal: true

require "test_helper"

# Keeps the removed names from creeping back into lib/.
#
# Its twin (legacy_tree_is_alias_only_test.rb) proved the v1 trees held no
# logic; the trees are gone and so is that test. This one used to prove the
# core did not reach BACK into them, which is what made the deletion a
# `git rm`. The deletion has happened -- a legacy `require` in lib/ now fails
# loudly on its own -- so the surviving job is the quiet half: a NAME in a
# string, a user-facing message or a docstring that mentions
# `Capybara::Screenshot.*`, `SnapDiff::Drivers.available` or
# `shift_distance_limit` still parses fine and simply lies.
#
# Scope: every file under lib/. The exclusion list this gate used to carry
# (legacy_shims.rb, deprecation.rb -- files that existed to BUILD the v1
# surface) is empty: they were deleted, not excluded.
#
# WHOLE-LINE comments are ignored: "ex +SnapDiff.config.active?+" on its
# own line is history, not a dependency. Everything else on a code line
# counts, strings and trailing comments included -- a user-facing message
# naming a legacy accessor is a legacy reference that survives the deletion
# and starts lying the day it happens, and a trailing note on a live line is
# close enough to the code to be worth keeping honest. Move such a note to
# its own line if the gate objects.
class CoreTreeHasNoLegacyDepsTest < ActiveSupport::TestCase
  LIB = Pathname.new(__dir__).join("../../lib").expand_path

  # EMPTY, and it must stay that way. It named the two files that built the v1
  # surface (legacy_shims.rb, deprecation.rb); 2.1 deleted them rather than
  # exempting them, so there is nothing left under lib/ this gate skips.
  DELETED_WITH_LEGACY_TREES = [].freeze

  CORE_FILES = (
    [LIB.join("snap_diff.rb")] + Dir[LIB.join("snap_diff/**/*.rb")].map { |p| Pathname.new(p) }
  ).sort.reject { |file| DELETED_WITH_LEGACY_TREES.include?(file.relative_path_from(LIB).to_s) }.freeze

  # A require of anything in the v1 trees: `capybara/screenshot/...`,
  # `capybara_screenshot_diff...`, `capybara-screenshot-diff`. Plain
  # `require "capybara"` / `"capybara/dsl"` is the base gem, not this gem's
  # legacy tree, so it must not match.
  #
  # The `(\.{1,2}/)*` is load-bearing: every core file sits one directory
  # below lib/, so `require_relative "../capybara/screenshot/diff/version"`
  # reaches the v1 tree and really loads it. Anchoring straight on the quote
  # let that through.
  LEGACY_REQUIRE = %r{\Arequire(_relative)?\s+["'](\.{1,2}/)*capybara(/screenshot|_screenshot_diff|-screenshot-diff)}

  # A read or write of a v1 namespace constant.
  LEGACY_CONSTANT = /(?<![\w:])(?:::)?(?:Capybara::Screenshot|CapybaraScreenshotDiff)\b/

  # The OTHER half of what 2.1 removed -- the driver abstraction and the
  # chunky_png-only setting. Same reasoning as LEGACY_CONSTANT: a core file
  # naming one of these in a message or a default is a promise the gem can no
  # longer keep.
  REMOVED_SURFACE = /
    SnapDiff::Driver\b
    |SnapDiff::Drivers\.(loaded|available|for|registry|detect_available)\b
    |AVAILABLE_DRIVERS
    |LOADED_DRIVERS
    |ChunkyPNGDriver
    |shift_distance_limit
    |silence_deprecations
  /x

  # THE ALLOWLIST -- the whole point of this gate is that it shrinks.
  #
  # Keyed by path relative to lib/, valued by the EXACT offending code lines
  # that are tolerated there, each with a written reason. Line-level, not
  # file-level, on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # EMPTY. It was seeded with all 64 core->legacy edges that existed the day
  # the gate was written, and every one of them is gone. Keep it empty: an
  # entry is a decision to keep a core->legacy edge across the 2.1 deletion,
  # so it needs a written reason here AND an ADR-008 update -- never just a
  # red build turned green.
  ALLOWED = {}.freeze

  test "no core file requires or references the v1 namespaces" do
    refute_empty CORE_FILES, "core glob matched nothing -- the gate would pass vacuously"

    offenders = CORE_FILES.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      lib/ names something 2.1 removed -- the v1 compatibility trees, the
      driver abstraction, or shift_distance_limit. Repoint these at what the
      gem actually has (`SnapDiff.config.*`, `SnapDiff::Drivers::VipsDriver`,
      `require "snap_diff/..."`):

      #{offenders.join("\n")}
    MSG
  end

  test "the allowlist names only lines that still exist" do
    stale = ALLOWED.flat_map do |path, lines|
      file = LIB.join(path)
      # A deleted file is the most stale an entry can get; report it rather
      # than letting Pathname#read blow up with Errno::ENOENT.
      next ["#{path}: allowlisted file no longer exists"] unless file.exist?

      present = significant_lines(file).map(&:first)
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
        elsif REMOVED_SURFACE.match?(line) then "names a surface 2.1 removed"
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
