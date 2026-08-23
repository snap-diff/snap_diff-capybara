# frozen_string_literal: true

require "test_helper"

class PendingScreenshotsMessageTest < ActiveSupport::TestCase
  teardown do
    SnapDiff.reset
  end

  test "returns nil when pending_if_new is disabled" do
    SnapDiff.config.stub(:pending_if_new, false) do
      SnapDiff.session.record_new_screenshot("a")

      assert_nil SnapDiff.pending_screenshots_message
    end
  end

  test "returns nil when pending_if_new is enabled but no new screenshots were recorded" do
    SnapDiff.config.stub(:pending_if_new, true) do
      assert_nil SnapDiff.pending_screenshots_message
    end
  end

  test "returns the baseline message listing recorded screenshot names" do
    SnapDiff.config.stub(:pending_if_new, true) do
      SnapDiff.session.record_new_screenshot("a")
      SnapDiff.session.record_new_screenshot("b")

      assert_equal(
        "No baseline for: a, b. Commit the captured screenshots to record them.",
        SnapDiff.pending_screenshots_message
      )
    end
  end

  test "reads from the calling thread's own registry, not other threads'" do
    SnapDiff.config.stub(:pending_if_new, true) do
      other_thread_result = Thread.new {
        SnapDiff.session.record_new_screenshot("other-thread")
        SnapDiff.pending_screenshots_message
      }.value

      assert_equal(
        "No baseline for: other-thread. Commit the captured screenshots to record them.",
        other_thread_result
      )
      assert_nil SnapDiff.pending_screenshots_message
    end
  end
end
