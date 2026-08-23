# frozen_string_literal: true

require "test_helper"

# The REVERSE of legacy_tree_is_alias_only_test.rb, and the other half of
# what makes the legacy removal a `git rm`.
#
# That test proves the v1 trees hold no logic. This one proves the canonical
# core does not reach BACK into them -- which is the half that actually
# breaks the gem if it is wrong: as long as any file under lib/snap_diff/
# requires a `capybara/...` path or reads a `Capybara::Screenshot.*` /
# `CapybaraScreenshotDiff::*` constant, deleting lib/capybara* leaves a core
# that no longer loads.
#
# Scope: everything the legacy deletion KEEPS. Files that are themselves part
# of the deletion set (DELETED_WITH_LEGACY_TREES below) live under lib/snap_diff/ only
# because the generator for the v1 surface has to be code, and the v1 trees
# have to stay alias-only -- they are legacy by design and go with it.
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

  # Deleted alongside lib/capybara* in 2.1: these files exist to BUILD the
  # v1 compatibility surface (const_missing shims, the legacy config
  # accessor generator, the deprecation channel that announces both).
  DELETED_WITH_LEGACY_TREES = %w[
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
  ].freeze

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

  # THE ALLOWLIST -- the whole point of this gate is that it shrinks.
  #
  # Keyed by path relative to lib/, valued by the EXACT offending code lines
  # that are tolerated there, each with a written reason. Line-level, not
  # file-level, on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # EMPTY. It was seeded with all 64 core->legacy edges that existed the day
  # the gate was written, and every one of them is gone. Keep it empty: an
  # entry is a decision to keep a core->legacy edge across the legacy deletion,
  # so it needs a written reason here AND an ADR-008 update -- never just a
  # red build turned green.
  ALLOWED = {}.freeze

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
