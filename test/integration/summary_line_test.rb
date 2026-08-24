# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# The end-of-run summary line, asserted on a REAL run of a user's test file
# (test/fixtures/summary_line_case.rb) in a fresh process, against real
# committed git baselines.
#
# In-process only would not do: three separate causes produced a green suite
# that compared nothing (no committed baseline, zero system tests actually
# run, an inherited GIT_DIR redirecting baseline lookup). None of them is
# visible to a per-assertion test -- no assertion runs. What catches all
# three is what the finished process printed, so that is what is asserted.
class SummaryLineTest < ActiveSupport::TestCase
  test "a passing run reports what it verified" do
    out, status = run_case("verified")

    assert status.success?, out
    assert_includes out, "[snap_diff] 1 verified, 0 changed, 0 new (not verified)."
  end

  test "a run that changed and captured a new screenshot counts all three, and keeps the report path" do
    out, status = run_case("verified,changed,new")

    refute status.success?, out
    assert_includes out, "[snap_diff] 2 verified, 1 changed, 1 new (not verified)."
    # Its own line since the counts left the HTML reporter (issue #269): the
    # counts print for everyone, the report path only when a file was written.
    assert_match(%r{^\[snap_diff\] Report: /\S+snap_diff_report\.html$}, out)
    # Exactly once. Reporting prints the counts and the HTML reporter prints
    # the path; if the reporter ever carries the counts again, the run ends
    # on the same line twice.
    assert_equal 1, out.scan("verified,").size, "the counts line was printed more than once"
  end

  # The case this line exists for: `rake test` running zero system tests, or
  # an inherited GIT_DIR sending every baseline lookup to the wrong repo.
  # Nothing else in the output says a word about it.
  test "a run that verified nothing says so, unmissably" do
    out, status = run_case("")

    assert status.success?, out
    assert_includes out, "[snap_diff] 0 verified, 0 changed, 0 new (not verified)."
    assert_includes out, "NOTHING WAS VERIFIED"
  end

  # The summary is the only thing that can see a run where zero system tests
  # executed, or where an inherited GIT_DIR redirected every baseline lookup.
  # It shipped registered by `snap_diff/reporters/html` -- so the documented
  # Rails setup, which requires only the Minitest integration, printed
  # nothing at all. Counting is core honesty; writing an HTML file is a
  # feature, and only the feature is opt-in.
  test "the summary prints with no reporter registered" do
    out, status = run_case("verified", reporter: false)

    assert status.success?, out
    assert_includes out, "[snap_diff] 1 verified, 0 changed, 0 new (not verified)."
    refute_includes out, "Report:", "no reporter was registered, so no report was written"
  end

  test "a run that verified nothing still shouts with no reporter registered" do
    out, status = run_case("", reporter: false)

    assert status.success?, out
    assert_includes out, "[snap_diff] 0 verified, 0 changed, 0 new (not verified)."
    assert_includes out, "NOTHING WAS VERIFIED"
  end

  # `record: :all` (#274) re-records without comparing. Through the summary
  # path (#269) that is neither verified nor changed, and NOT "new" either
  # -- there was a baseline, it was just not consulted. Asserted on a
  # finished process because the two features never met before this branch.
  test "a run that only re-recorded says so instead of crying NOTHING WAS VERIFIED" do
    out, status = run_case("rerecorded")

    assert status.success?, out
    assert_includes out, "[snap_diff] 0 verified, 0 changed, 0 new (not verified). 1 re-recorded (not verified)."
    # The shout is for an UNEXPLAINED zero. The user asked for this one, and
    # a false alarm here is how the real alarm stops being read.
    refute_includes out, "NOTHING WAS VERIFIED"
    assert_includes out, "record: :all re-recorded 1 screenshot WITHOUT comparing: rerecorded"
  end

  test "a mixed run counts verified and re-recorded separately" do
    out, status = run_case("verified,rerecorded")

    assert status.success?, out
    assert_includes out, "[snap_diff] 1 verified, 0 changed, 0 new (not verified). 1 re-recorded (not verified)."
  end

  private

  # Builds a throwaway git repo with COMMITTED baselines for `verified` and
  # `changed` (none for `new`), then runs the user's test file against it.
  def run_case(cases, reporter: true)
    Dir.mktmpdir do |dir|
      # macOS hands out /var/... symlinks; git reports the physical path, and
      # baseline lookup is a relative_path_from between the two.
      repo = File.realpath(dir)
      FileUtils.mkdir_p("#{repo}/screenshots")
      FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/verified.png")
      FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/changed.png")
      FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/rerecorded.png")
      git = ["git", "-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=t"]
      Open3.capture2e(*git, "init", "-q")
      Open3.capture2e(*git, "add", "screenshots")
      Open3.capture2e(*git, "commit", "-qm", "baselines")

      Open3.capture2e(
        {"SNAP_ROOT" => repo, "SNAP_IMAGES" => TEST_IMAGES_DIR.to_s, "SNAP_CASES" => cases, "CI" => nil,
         "SNAP_NO_REPORTER" => (reporter ? nil : "1")},
        RbConfig.ruby, "-Ilib", "-Itest", file_fixture("summary_line_case.rb").to_s
      )
    end
  end
end
