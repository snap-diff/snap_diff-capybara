# frozen_string_literal: true

require "test_helper"

# Wrote the 2.1 deletion; still earns its keep after it.
#
# Before: this gate and legacy_tree_is_alias_only_test.rb were the two halves
# of what made the removal a plain `git rm` -- one proved the v1 trees held
# no logic, this one proved the canonical core never reached BACK into them.
# The alias-only half died with test/legacy/.
#
# After: the trees are gone, so a `require "capybara/screenshot/..."` fails
# loudly on its own. What does NOT fail loudly is the rest -- a user-facing
# message telling someone to set `Capybara::Screenshot.tolerance`, a
# docstring pointing at a forwarder, a rescue naming an old constant. Those
# survive the deletion and start lying the day it lands. This gate is what
# keeps the removed names from creeping back into the code that shipped
# without them.
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

  # No exclusions: snap_diff/legacy_shims.rb and snap_diff/deprecation.rb
  # were the two files under here that existed to BUILD the v1 surface, and
  # 2.1 deleted them with it. Everything left is canonical by definition.
  CORE_FILES = (
    [LIB.join("snap_diff.rb")] + Dir[LIB.join("snap_diff/**/*.rb")].map { |p| Pathname.new(p) }
  ).sort.freeze

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

  # THE ALLOWLIST -- the whole point of this gate is that it shrinks.
  #
  # Keyed by path relative to lib/, valued by the EXACT offending code lines
  # that are tolerated there, each with a written reason. Line-level, not
  # file-level, on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # EMPTY. It was seeded with all 64 core->legacy edges that existed the day
  # the gate was written, and every one of them is gone -- along with the
  # trees they pointed at. An entry now is a decision to name a REMOVED api
  # in shipped code, so it needs a written reason here AND an ADR-008
  # update -- never just a red build turned green.
  ALLOWED = {}.freeze

  test "no core file requires or references the v1 namespaces" do
    refute_empty CORE_FILES, "core glob matched nothing -- the gate would pass vacuously"

    offenders = CORE_FILES.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      The canonical core names the v1 compatibility surface, which 2.1
      removed. Repoint these at their snap_diff/* equivalents
      (`SnapDiff.config.*`, `SnapDiff::Drivers.*`, `require "snap_diff/..."`) --
      a require here does not resolve at all, and a message or docstring
      here sends users to an API that is gone:

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
