# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class StableScreenshoterTest < ActionDispatch::IntegrationTest
        include TestMethodsStub

        test "#take_stable_screenshot several iterations to take stable screenshot" do
          image_compare_stub = build_image_compare_stub

          mock = ::Minitest::Mock.new(image_compare_stub)

          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, true)

          ImageCompare.stub :new, mock do
            take_stable_screenshot_with("tmp/02_a.png")
          end

          mock.verify
        end

        test "#take_stable_screenshot without wait raises any error" do
          assert_raises ArgumentError, "wait should be provided" do
            take_stable_screenshot_with("tmp/02_a.png", wait: nil)
          end
        end

        test "#take_stable_screenshot without stability_time_limit raises any error" do
          assert_raises ArgumentError, "stability_time_limit should be provided" do
            take_stable_screenshot_with("tmp/02_a.png", stability_time_limit: nil)
          end
        end

        test "#take_comparison_screenshot deletes runtime files on completion" do
          image_compare_stub = build_image_compare_stub

          mock = ::Minitest::Mock.new(image_compare_stub)
          mock.expect(:quick_equal?, false)
          mock.expect(:quick_equal?, true)

          assert_not (Capybara::Screenshot.root / "02_a.png").exist?

          ImageCompare.stub :new, mock do
            StableScreenshoter
              .new({stability_time_limit: 0.5, wait: 0.5}, image_compare_stub.driver_options)
              .take_comparison_screenshot("tmp/02_a.png")
          end

          mock.verify
          assert_empty Dir[Capybara::Screenshot.root / "**/02_a.attempt_*.png"]
          assert (Capybara::Screenshot.root / "02_a.png").exist?
          assert_not_predicate (Capybara::Screenshot.root / "02_a.png").size, :zero?
        end

        test "#take_comparison_screenshot fail on missing find stable image in time and generates annotated history screenshots" do
          screenshot_path = Pathname.new("tmp/01_a.png")

          # Stub annotated files for generated comparison annotations
          # We need to have different from screenshot_path name because of other stubs
          annotated_screenshot_path = Pathname.new("tmp/02_a.png")
          annotated_attempts_paths = [
            [annotated_screenshot_path.sub_ext(".attempt_01.latest.png"), annotated_screenshot_path.sub_ext(".attempt_01.committed.png")],
            [annotated_screenshot_path.sub_ext(".attempt_02.latest.png"), annotated_screenshot_path.sub_ext(".attempt_02.committed.png")]
          ]

          FileUtils.touch(annotated_attempts_paths)

          mock = ::Minitest::Mock.new(build_image_compare_stub(equal: false))
          annotated_attempts_paths.reverse_each do |(latest_path, committed_path)|
            mock.reporter.expect(:annotated_image_path, latest_path.to_s)
            mock.reporter.expect(:annotated_base_image_path, committed_path.to_s)
          end

          assert_raises RuntimeError, "Could not get stable screenshot within 1s" do
            ImageCompare.stub :new, mock do
              # Wait time is less then stability time, which will generate problem
              StableScreenshoter
                .new({stability_time_limit: 0.5, wait: 0.5}, build_image_compare_stub(equal: false).driver_options)
                .take_comparison_screenshot(screenshot_path.to_s)
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
          FileUtils.rm_rf Dir["tmp/01_a*.png"]
        end
      end
    end
  end
end
