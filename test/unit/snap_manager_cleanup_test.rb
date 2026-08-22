# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  # Guard #3 from the v2 core-redesign acceptance contract (D7).
  #
  # Documents the previously-dead class-method cleanup path:
  # `SnapDiff::SnapManager.instance` used to build a brand-new manager on every call, so
  # `SnapDiff::SnapManager.snapshot` tracked snapshots on one throwaway instance and
  # `SnapDiff::SnapManager.cleanup!` iterated the empty set of another — test_helper's
  # teardown cleanup had never deleted anything through the tracked path.
  # These tests were RED before SnapDiff::SnapManager.instance was memoized per thread.
  class SnapManagerCleanupTest < ActiveSupport::TestCase
    test ".instance returns the same manager within a thread" do
      assert_same SnapDiff::SnapManager.instance, SnapDiff::SnapManager.instance
    end

    test ".instance is rebuilt when the screenshot root changes" do
      original = SnapDiff::SnapManager.instance

      Dir.mktmpdir do |dir|
        Capybara::Screenshot.root = dir

        rebuilt = SnapDiff::SnapManager.instance

        assert_not_same original, rebuilt
        assert_equal Pathname.new(Capybara::Screenshot.screenshot_area_abs), rebuilt.root
      end
    end

    test ".cleanup! deletes files of snapshots tracked via the class-method path" do
      snap = SnapDiff::SnapManager.snapshot("cleanup_guard")
      provision(snap)

      assert_predicate snap.path, :exist?
      assert_predicate snap.base_path, :exist?

      SnapDiff::SnapManager.cleanup!

      assert_not snap.path.exist?, "cleanup! must delete the actual screenshot tracked by SnapDiff::SnapManager.snapshot"
      assert_not snap.base_path.exist?, "cleanup! must delete the base screenshot tracked by SnapDiff::SnapManager.snapshot"
    end

    test ".cleanup! in one thread does not delete snapshots tracked by another thread" do
      barrier = Queue.new

      thread_b_snap = nil
      thread_b = Thread.new do
        thread_b_snap = SnapDiff::SnapManager.snapshot("cleanup_guard_thread_b")
        provision(thread_b_snap)
        barrier.pop # wait until thread A has cleaned up
      end

      thread_a = Thread.new do
        snap = SnapDiff::SnapManager.snapshot("cleanup_guard_thread_a")
        provision(snap)
        Thread.pass until thread_b_snap&.path&.exist?

        SnapDiff::SnapManager.cleanup!
        snap
      end

      thread_a_snap = thread_a.value
      barrier << :done
      thread_b.join

      assert_not thread_a_snap.path.exist?, "thread A's own snapshot should be cleaned up"
      assert_predicate thread_b_snap.path, :exist?, "thread B's snapshot must survive thread A's cleanup!"
    ensure
      thread_b_snap&.delete!
    end

    private

    def provision(snap)
      snap.path.dirname.mkpath
      FileUtils.cp(fixture_image_path_from("a"), snap.path)
      FileUtils.cp(fixture_image_path_from("a"), snap.base_path)
    end
  end
end
