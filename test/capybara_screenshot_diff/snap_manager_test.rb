# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class SnapManagerTest < ActiveSupport::TestCase
    setup do
      @manager = SnapManager.new(Dir.mktmpdir("snap_diff-storage"))
    end

    teardown do
      @manager.clean!
    end

    test "#provision_snap_with copies the file to the snap path" do
      snap = @manager.snap_for("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path)

      assert_predicate snap.path, :exist?
      assert_not_predicate snap.base_path, :exist?
    end

    test "#provision_snap_with populate the base version of the snapshot" do
      snap = @manager.snap_for("test_image")
      path = fixture_image_path_from("a")

      @manager.provision_snap_with(snap, path, version: :base)

      assert_not_predicate snap.path, :exist?
      assert_predicate snap.base_path, :exist?
    end
  end
end
