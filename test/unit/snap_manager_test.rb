# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class SnapManagerTest < ActiveSupport::TestCase
    setup do
      @manager = SnapDiff::SnapManager.new(Dir.mktmpdir("snap_diff-storage"))
    end

    teardown do
      @manager.cleanup!
    end

    test "#provision_snap_with copies the file to the snap path" do
      snap = @manager.snapshot("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path)

      assert_predicate snap.path, :exist?
      assert_not_predicate snap.base_path, :exist?
    end

    test "#provision_snap_with populate the base version of the snapshot" do
      snap = @manager.snapshot("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path, version: :base)

      assert_not_predicate snap.path, :exist?
      assert_predicate snap.base_path, :exist?
    end

    test "#screenshots_dir returns all created snapshots" do
      assert_equal [], @manager.snapshots.to_a

      snap = @manager.snapshot("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path)
      assert_equal [snap], @manager.snapshots.to_a
    end

    test "#screenshots_dir ignores attempts" do
      assert_equal [], @manager.snapshots.to_a

      snap = @manager.snapshot("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path, version: :attempt)

      assert_equal [snap], @manager.snapshots.to_a
    end

    test "#snapshot overrides the file extension" do
      snap = @manager.snapshot("test_image")
      assert_equal "test_image", snap.full_name
      assert_includes snap.path.to_s, "test_image.png"
      assert_includes snap.base_path.to_s, "test_image.base.png"
      assert_includes snap.next_attempt_path!.to_s, "test_image.attempt_00.png"
    end

    # With a per-thread long-lived manager, cleanup! must also empty the
    # tracked set — otherwise it grows for the whole run and a later cleanup!
    # can delete a path an earlier test tracked but this test re-provisioned.
    test "#cleanup! empties the tracked set" do
      snap = @manager.snapshot("tracked_then_cleaned")
      @manager.provision_snap_with(snap, fixture_image_path_from("a"))

      @manager.cleanup!

      assert_empty @manager.snapshots
    end

    # Store-API split guard (v2 amendment item 1): #path_for is the pure
    # lookup half of what #snapshot used to be used for. Callers that only
    # need paths (e.g. dsl_test's post-capture assertions) must be able to
    # look up without registering the name for cleanup!.
    test "#path_for resolves the same paths as #snapshot" do
      registered = @manager.snapshot("split_guard")
      looked_up = @manager.path_for("split_guard")

      assert_equal registered.path, looked_up.path
      assert_equal registered.base_path, looked_up.base_path
    end

    test "#path_for never registers the snapshot for cleanup" do
      @manager.path_for("split_guard")

      assert_empty @manager.snapshots.to_a
    end

    test ".path_for is a pure lookup on the shared instance" do
      tracked_before = SnapDiff::SnapManager.instance.snapshots.dup

      looked_up = SnapDiff::SnapManager.path_for("split_guard_class")

      assert_equal tracked_before, SnapDiff::SnapManager.instance.snapshots

      registered = SnapDiff::SnapManager.snapshot("split_guard_class")
      assert_includes SnapDiff::SnapManager.instance.snapshots, registered
      assert_equal registered.path, looked_up.path
    end

    test "#cleanup! removes diff artifacts created by reporters" do
      snap = @manager.snapshot("test_image")
      source = fixture_image_path_from("a")
      @manager.provision_snap_with(snap, source)
      @manager.provision_snap_with(snap, source, version: :base)

      diff_path = snap.path.sub_ext(".diff.png")
      base_diff_path = snap.path.sub_ext(".base.diff.png")
      heatmap_path = snap.path.sub_ext(".heatmap.diff.png")
      [diff_path, base_diff_path, heatmap_path].each { |p| FileUtils.cp(source, p) }

      @manager.cleanup!

      assert_not diff_path.exist?, "diff artifact should be cleaned up"
      assert_not base_diff_path.exist?, "base diff artifact should be cleaned up"
      assert_not heatmap_path.exist?, "heatmap diff artifact should be cleaned up"
    end
  end
end
