# frozen_string_literal: true

require "test_helper"

# The TEST-TREE half of the split that core_tree_has_no_legacy_deps_test.rb
# guards for lib/.
#
# Before 2.1 this gate protected a FUTURE deletion: a test asserting legacy
# behaviour passed then and would fail the day the v1 trees went. The deletion
# has landed, so a legacy `require` now fails by itself and this gate no longer
# has to predict anything. It stays for the half that still does not fail on
# its own -- a legacy NAME in a string, a heredoc-embedded subprocess script,
# an assertion message or a docstring. Those survive the deletion and start
# lying the moment it happens.
#
# Scope: test/unit/ and test/integration/ -- the whole suite now that
# test/legacy/ is gone.
#
# WHOLE-LINE comments are ignored, same as the twin gate: a comment
# explaining that a forwarder used to live under the old name is history, not
# a dependency. Everything else on a code line counts, strings included -- a
# subprocess script embedded in a heredoc runs, and a legacy require inside
# one dies with the trees just as loudly as one at the top of the file.
class CanonicalSuiteHasNoLegacyRefsTest < ActiveSupport::TestCase
  TEST_ROOT = Pathname.new(__dir__).join("..").expand_path

  # This file cannot scan itself: a line-level allowlist has to quote the
  # exact lines it blesses, and every such quote is itself a legacy
  # reference. Scanning self would demand an allowlist entry for the
  # allowlist, whose text is again an offence -- no fixed point exists.
  SELF = Pathname.new(File.expand_path(__FILE__))

  # The compat surface's own test, excluded whole for the same reason as SELF.
  # Since the ADR-008 amendment (2026-08-24) the v1 NAMES are a kept, permanent
  # alias surface -- so one test has to exercise them, written as the affected
  # user's own code. A line allowlist for a file whose every line is the
  # subject buys nothing; the gate still holds for every other test file.
  COMPAT_SURFACE_TESTS = ["unit/compat_surface_test.rb"].freeze

  EXCLUDED = ([SELF] + COMPAT_SURFACE_TESTS.map { |rel| TEST_ROOT.join(rel) }).freeze

  ALL_FILES = (
    Dir[TEST_ROOT.join("unit/**/*_test.rb")] + Dir[TEST_ROOT.join("integration/**/*_test.rb")]
  ).map { |path| Pathname.new(path) }.sort.freeze

  CANONICAL_FILES = ALL_FILES.reject { |file| EXCLUDED.include?(file) }.freeze

  # A require of a doomed path: the v1 trees (`capybara/screenshot/...`,
  # `capybara_screenshot_diff...`, the `capybara-screenshot-diff` gem-name
  # entry) and the two core files that build the v1 surface and go with it.
  # Plain `require "capybara"` / `"capybara/minitest"` is the base gem and
  # must not match.
  #
  # Unanchored, unlike the lib-side twin: tests drive subprocesses, so a
  # legacy require is as likely to sit inside a heredoc or a `-e` string as
  # at the top of the file, and both really load it. The optional backslash
  # covers the escaped-quote form those scripts use.
  LEGACY_REQUIRE = %r{
    require(_relative)?\s+\\?["'](\.{1,2}/)*
    (capybara(/screenshot|_screenshot_diff|-screenshot-diff)|snap_diff/(legacy_shims|deprecation))
  }x

  # A read or write of a v1 namespace constant.
  LEGACY_CONSTANT = /(?<![\w:])(?:::)?(?:Capybara::Screenshot|CapybaraScreenshotDiff)\b/

  # The canonical-LOOKING half of what 2.1 removed: names spelled under
  # SnapDiff:: that were nonetheless defined in the deleted files, so they
  # resolve to nothing now. Kept as text patterns because that is exactly how
  # they come back -- in a docstring or an assertion message, where Ruby will
  # not complain.
  #
  # SnapDiff.silence_deprecations and SnapDiff::Removal are here now: 2.0 kept
  # them alive to announce this release, and this release removes the thing
  # they announced, so there is nothing left to silence.
  LEGACY_SHIM_SURFACE = /
    SnapDiff\.start\b
    |SnapDiff::Deprecation\b
    |SnapDiff::Removal\b
    |SnapDiff::Driver\b
    |SnapDiff::Drivers\.(loaded|available|for|registry|detect_available)\b
    |AVAILABLE_DRIVERS
    |LOADED_DRIVERS
    |silence_deprecations
    |suppress_migration_notice
  /x

  # THE ALLOWLIST -- keyed by path relative to test/, valued by the EXACT
  # offending code lines tolerated there, each with a written reason.
  # Line-level on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # Two entries, and both are gates rather than tests of behaviour: a detector
  # has to spell what it detects. A third entry is a signal that the suite is
  # still entangled with a removed surface -- it needs a decision, not a green
  # build.
  ALLOWED = {
    # The twin gate's own pattern literals. A detector has to spell what it
    # detects; these lines assert nothing and scan lib/, not the suite.
    "unit/core_tree_has_no_legacy_deps_test.rb" => [
      'LEGACY_CONSTANT = /(?<![\w:])(?:::)?(?:Capybara::Screenshot|CapybaraScreenshotDiff)\b/',
      'SnapDiff::Driver\b',
      '|SnapDiff::Drivers\.(loaded|available|for|registry|detect_available)\b',
      "|AVAILABLE_DRIVERS",
      "|LOADED_DRIVERS",
      "|ChunkyPNGDriver",
      "|shift_distance_limit",
      "|silence_deprecations"
    ],
    # Same, for the gate that proves the removed surface STAYS removed. Its
    # tables are the removal list itself -- it cannot assert a name is gone
    # without spelling it -- and every line here is data in a table, never an
    # assertion about legacy behaviour.
    "unit/removed_surface_test.rb" => [
      "SnapDiff::Deprecation",
      "SnapDiff::Removal",
      "SnapDiff::Driver",
      "SnapDiff::Drivers::AVAILABLE_DRIVERS",
      "REMOVED_METHODS = %w[start silence_deprecations silence_deprecations=].freeze"
    ]
  }.freeze

  test "no canonical test references the legacy namespaces or entry points" do
    refute_empty CANONICAL_FILES, "canonical glob matched nothing -- the gate would pass vacuously"
    assert_equal ALL_FILES.size - EXCLUDED.size, CANONICAL_FILES.size,
      "an exclusion no longer names a scanned file, so this gate is scanning itself or nothing"
    EXCLUDED.each { |file| assert file.exist?, "#{file} is excluded from this gate but does not exist" }

    offenders = CANONICAL_FILES.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      Test(s) name a surface 2.1 removed. The v1 trees, the deprecation
      channel and the driver abstraction are gone, so these names resolve to
      nothing -- and where they sit in a string or a docstring, nothing else
      will say so.

      Rewrite against what the gem actually has (`SnapDiff.config.*`,
      `SnapDiff.configure`, `SnapDiff::Os`, `SnapDiff::Minitest::Assertions`,
      `SnapDiff::Drivers::VipsDriver`, `require "snap_diff/..."`):

      #{offenders.join("\n")}
    MSG
  end

  test "the allowlist names only lines that still exist" do
    stale = ALLOWED.flat_map do |path, lines|
      file = TEST_ROOT.join(path)
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
    rel = file.relative_path_from(TEST_ROOT).to_s
    allowed = ALLOWED.fetch(rel, [])

    significant_lines(file).filter_map do |line, number|
      next if allowed.include?(line)

      reason =
        if LEGACY_REQUIRE.match?(line) then "requires a doomed path"
        elsif LEGACY_CONSTANT.match?(line) then "references a v1 namespace constant"
        elsif LEGACY_SHIM_SURFACE.match?(line) then "uses a shim-only name that the deletion removes"
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
