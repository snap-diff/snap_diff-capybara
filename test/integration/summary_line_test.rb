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
    assert_match(
      %r{\[snap_diff\] 2 verified, 1 changed, 1 new \(not verified\)\. Report: /\S+snap_diff_report\.html},
      out
    )
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

  private

  # Builds a throwaway git repo with COMMITTED baselines for `verified` and
  # `changed` (none for `new`), then runs the user's test file against it.
  def run_case(cases)
    Dir.mktmpdir do |dir|
      # macOS hands out /var/... symlinks; git reports the physical path, and
      # baseline lookup is a relative_path_from between the two.
      repo = File.realpath(dir)
      FileUtils.mkdir_p("#{repo}/screenshots")
      FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/verified.png")
      FileUtils.cp(fixture_image_path_from("a"), "#{repo}/screenshots/changed.png")
      git = ["git", "-C", repo, "-c", "user.email=t@example.com", "-c", "user.name=t"]
      Open3.capture2e(*git, "init", "-q")
      Open3.capture2e(*git, "add", "screenshots")
      Open3.capture2e(*git, "commit", "-qm", "baselines")

      Open3.capture2e(
        {"SNAP_ROOT" => repo, "SNAP_IMAGES" => TEST_IMAGES_DIR.to_s, "SNAP_CASES" => cases, "CI" => nil},
        RbConfig.ruby, "-Ilib", "-Itest", file_fixture("summary_line_case.rb").to_s
      )
    end
  end
end
