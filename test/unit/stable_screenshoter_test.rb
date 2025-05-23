# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class StableScreenshoterTest < ActiveSupport::TestCase
        include CapybaraScreenshotDiff::DSLStub

        setup do
          @manager = CapybaraScreenshotDiff::SnapManager.new(Capybara::Screenshot.root / "stable_screenshoter_test")
          @manager.create_output_directory_for
        end

        teardown do
          @manager.cleanup!
        end

        test "#take_stable_screenshot retries until images are stable across iterations" do
          image_compare_stub = build_image_compare_stub

          mock = ::Minitest::Mock.new(image_compare_stub)

          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, true)

          ImageCompare.stub :new, mock do
            snap = @manager.snapshot("02_a")
            take_stable_screenshot_with(snap)
          end

          assert mock.verify
        end

        test "#take_stable_screenshot raises ArgumentError when wait parameter is nil" do
          assert_raises ArgumentError, "wait should be provided" do
            take_stable_screenshot_with(@manager.snapshot("02_a"), wait: nil)
          end
        end

        test "#take_stable_screenshot raises ArgumentError when stability_time_limit is nil" do
          assert_raises ArgumentError, "stability_time_limit should be provided" do
            take_stable_screenshot_with(@manager.snapshot("02_a"), stability_time_limit: nil)
          end
        end

        test "#take_comparison_screenshot cleans up temporary files after successful comparison" do
          image_compare_stub = build_image_compare_stub

          mock = ::Minitest::Mock.new(image_compare_stub)
          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, true)

          snap = @manager.snapshot("02_a")
          assert_not_predicate snap.path, :exist?

          ImageCompare.stub :new, mock do
            Capybara::Screenshot::Diff::StableScreenshoter
              .new({stability_time_limit: 0.5, wait: 1}, image_compare_stub.driver_options)
              .take_comparison_screenshot(snap)
          end

          mock.verify
          assert_empty snap.find_attempts_paths
          assert_predicate snap.path, :exist?
          assert_not_predicate snap.path.size, :zero?
        end

        test "#take_comparison_screenshot raises UnstableImage when stability timeout is reached" do
          snap = @manager.snapshot("01_a")

          screenshot_path = snap.path

          # Stub annotated files for generated comparison annotations
          # We need to have different from screenshot_path name because of other stubs
          pseudo_snap_for_annotations = @manager.snapshot("02_a")
          annotated_screenshot_path = pseudo_snap_for_annotations.path
          annotated_attempts_paths = [
            [annotated_screenshot_path.sub_ext(".attempt_01.latest.png"), annotated_screenshot_path.sub_ext(".attempt_01.committed.png")],
            [annotated_screenshot_path.sub_ext(".attempt_02.latest.png"), annotated_screenshot_path.sub_ext(".attempt_02.committed.png")]
          ]

          FileUtils.touch(annotated_attempts_paths)

          mock = ::Minitest::Mock.new(build_image_compare_stub(equal: false))
          annotated_attempts_paths.reverse_each do |(actual_path, base_path)|
            mock.reporter.expect(:annotated_image_path, actual_path.to_s)
            mock.reporter.expect(:annotated_base_image_path, base_path.to_s)
          end

          assert_raises CapybaraScreenshotDiff::UnstableImage, "Could not get stable screenshot within 1s" do
            ImageCompare.stub :new, mock do
              # Wait time is less then stability time, which will generate problem
              Capybara::Screenshot::Diff::StableScreenshoter
                .new({stability_time_limit: 0.5, wait: 1}, build_image_compare_stub(equal: false).driver_options)
                .take_comparison_screenshot(snap)
            end
          end

          mock.verify
          mock.reporter.verify

          # There are no runtime files to find difference on stabilization
          assert_empty Dir["tmp/*_a*.latest.png"]
          assert_empty Dir["tmp/*_a*.committed.png"]

          # All stabilization files should be annotated
          last_annotation = screenshot_path.sub_ext(".attempt_02.png")
          assert_equal 0, last_annotation.size, "#{last_annotation.to_path} should be override with annotated version"
          last_annotation = screenshot_path.sub_ext(".attempt_01.png")
          assert_equal 0, last_annotation.size, "#{last_annotation.to_path} should be override with annotated version"
        ensure
          snap&.delete!
          pseudo_snap_for_annotations&.delete!
        end
      end
    end
  end
end
