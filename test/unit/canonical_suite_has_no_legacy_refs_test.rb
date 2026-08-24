# frozen_string_literal: true

require "test_helper"

# The TEST-TREE half of the split that core_tree_has_no_legacy_deps_test.rb
# guards for lib/.
#
# `rake test:canonical` is defined as "exactly what must still pass once
# test/legacy/ and the v1 trees are gone". A test that ASSERTS legacy
# behaviour from test/unit/ or test/integration/ is therefore a time bomb:
# it passes today and fails the day the deletion lands, long after its author
# has moved on. That has now happened three times in review -- a canonical
# surface table demanding a shim-only method, legacy-constant probes written
# into a canonical file, an umbrella guard that had to be relocated. Reviews
# caught all three; this catches the fourth.
#
# Scope: test/unit/ and test/integration/ -- the two trees `test:canonical`
# runs and the deletion keeps. test/legacy/ is deliberately NOT policed: its
# whole job is to exercise the legacy surface, and it is deleted with it.
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

  ALL_FILES = (
    Dir[TEST_ROOT.join("unit/**/*_test.rb")] + Dir[TEST_ROOT.join("integration/**/*_test.rb")]
  ).map { |path| Pathname.new(path) }.sort.freeze

  CANONICAL_FILES = ALL_FILES.reject { |file| file == SELF }.freeze

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

  # The canonical-looking half of the legacy surface: names that live under
  # SnapDiff:: but are DEFINED in legacy_shims.rb / deprecation.rb, so they
  # are deleted with the v1 trees (ADR-008 -- SnapDiff.configure is the
  # single config entry point). This is the shape of the first of the three
  # incidents: a canonical gate demanding SnapDiff.start.
  #
  # SnapDiff.silence_deprecations is deliberately NOT here: it moved to
  # snap_diff/removal.rb, a file the deletion keeps, because it is the one
  # switch that also silences the 2.1 removal warnings (chunky_png,
  # shift_distance_limit, the driver abstraction) -- which are announced from
  # core files and have nothing to do with the v1 namespaces.
  LEGACY_SHIM_SURFACE = /
    SnapDiff\.start\b
    |SnapDiff::Deprecation\b
    |suppress_migration_notice
  /x

  # THE ALLOWLIST -- keyed by path relative to test/, valued by the EXACT
  # offending code lines tolerated there, each with a written reason.
  # Line-level on purpose: a file with one blessed line must still fail on
  # the second.
  #
  # Two entries, and both are gates rather than tests of behaviour. A third
  # entry is a signal that canonical tests are still entangled with the
  # legacy surface -- it needs a decision, not a green build.
  ALLOWED = {
    # Simulates the deletion for real (copies lib/, removes the trees, loads
    # every canonical entry point). It names the deletion set and the edits
    # by construction, and asserts its own gate line can reject an intact
    # tree -- it cannot do that without spelling the doomed names.
    "unit/legacy_deletion_test.rb" => [
      '["snap_diff.rb", %(require "snap_diff/legacy_shims"), nil],',
      '%(require "capybara_screenshot_diff/minitest" if defined?(::Minitest)),',
      '%(require "capybara_screenshot_diff"),',
      'gate << "SnapDiff.start is still defined" if SnapDiff.respond_to?(:start)',
      'gate << "CapybaraScreenshotDiff is still defined" if defined?(CapybaraScreenshotDiff)',
      'assert_includes failure, "SnapDiff.start is still defined"'
    ],
    # The twin gate's own pattern literal. A detector has to spell what it
    # detects; the line asserts nothing about legacy behaviour and is deleted
    # with the trees it guards.
    "unit/core_tree_has_no_legacy_deps_test.rb" => [
      'LEGACY_CONSTANT = /(?<![\w:])(?:::)?(?:Capybara::Screenshot|CapybaraScreenshotDiff)\b/'
    ]
  }.freeze

  test "no canonical test references the legacy namespaces or entry points" do
    refute_empty CANONICAL_FILES, "canonical glob matched nothing -- the gate would pass vacuously"
    assert_equal ALL_FILES.size - 1, CANONICAL_FILES.size,
      "SELF no longer names a scanned file, so this gate is scanning itself or nothing"

    offenders = CANONICAL_FILES.flat_map { |file| offences(file) }

    assert_empty offenders, <<~MSG
      Canonical test(s) assert legacy behaviour. `rake test:canonical` is what
      must still pass once test/legacy/ and the v1 trees are deleted, so these
      lines are green today and red the day the deletion lands.

      Move the test to test/legacy/ (it dies with what it tests), or rewrite it
      against the canonical surface (`SnapDiff.config.*`, `SnapDiff::Os`,
      `SnapDiff::Minitest::Assertions`, `require "snap_diff/..."`):

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
