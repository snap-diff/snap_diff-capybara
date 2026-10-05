# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# AI triage end-to-end: REAL runs of a user's test file
# (test/fixtures/ai_triage_case.rb) in fresh processes -- real registry,
# real HTML reporter, real git baselines -- with a name-keyed fake backend,
# so no model download or network is involved. In-process unit tests would
# not catch a reporter that never gets registered, a gate that runs too
# late, or a report rendered before the store is filled; the finished
# process's output and files do.
class AiTriageTest < ActiveSupport::TestCase
  test "advisory mode logs and badges verdicts, and the pixel diff still fails" do
    out, status, report = run_case("verified,flaky,buggy")

    refute status.success?, out
    assert_includes out, "[snap_diff:ai] flaky: FLAKY (custom, similarity=0.999)"
    assert_includes out, "[snap_diff:ai] buggy: REAL_BUG (custom, similarity=0.42)"
    assert_includes out, "[snap_diff:ai] 2 diff(s) analyzed: 1 real_bug, 1 flaky"
    assert_includes report, '"verdict":"flaky"'
    assert_includes report, '"verdict":"real_bug"'
  end

  test "gate mode suppresses flaky diffs and keeps the suite green" do
    out, status, = run_case("flaky", fail_on: true)

    assert status.success?, out
    assert_includes out, "[snap_diff:ai] flaky: failure suppressed -- FLAKY (custom, similarity=0.999)"
  end

  test "gate mode still fails real bugs and quotes the verdict in the failure message" do
    out, status, = run_case("flaky,buggy", fail_on: true)

    refute status.success?, out
    assert_includes out, "[snap_diff:ai] flaky: failure suppressed -- FLAKY (custom, similarity=0.999)"
    assert_includes out, "Screenshot does not match for 'buggy'"
    assert_includes out, "AI triage: REAL_BUG (custom, similarity=0.42)"
  end

  private

  # Mirrors summary_line_test.rb: a throwaway git repo with COMMITTED
  # baselines, then the user's test file against it in a fresh process.
  # Returns [output, exit status, rendered HTML report (nil when absent)].
  def run_case(cases, fail_on: false)
    Dir.mktmpdir do |dir|
      # macOS hands out /var/... symlinks; git reports the physical path, and
      # baseline lookup is a relative_path_from between the two.
      repo = File.realpath(dir)
      FileUtils.mkdir_p("#{repo}/screenshots")
      %w[verified flaky buggy].each do |name|
        FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/#{name}.png")
      end
      git = ["git", "-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=t"]
      Open3.capture2e(*git, "init", "-q")
      Open3.capture2e(*git, "add", "screenshots")
      Open3.capture2e(*git, "commit", "-qm", "baselines")

      out, status = Open3.capture2e(
        {"SNAP_ROOT" => repo, "SNAP_IMAGES" => TEST_IMAGES_DIR.to_s, "SNAP_CASES" => cases, "CI" => nil,
         "SNAP_FAIL_ON" => (fail_on ? "1" : nil)},
        RbConfig.ruby, "-Ilib", "-Itest", file_fixture("ai_triage_case.rb").to_s
      )
      report_path = "#{repo}/screenshots/snap_diff_report.html"
      [out, status, (File.read(report_path) if File.exist?(report_path))]
    end
  end
end
