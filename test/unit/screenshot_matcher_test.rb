# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module Capybara
  module Screenshot
    module Diff
      # Guard #1 from the v2 core-redesign acceptance contract: pins
      # ScreenshotMatcher's current external behavior (D1-D4) in isolation
      # before the orchestration middle is redesigned. Until now the class had
      # no dedicated unit test at all — it was exercised only indirectly
      # through dsl_test stubs and full-browser integration tests.
      class ScreenshotMatcherTest < ActiveSupport::TestCase
        include CapybaraScreenshotDiff::DSLStub

        # A screenshoter probe that records the (capture_options,
        # comparison_options) split it was built with (D1) and writes a real
        # file so the rest of the flow proceeds.
        def recording_screenshoter(calls)
          Class.new do
            define_method(:initialize) do |capture_options, comparison_options|
              calls << [capture_options, comparison_options]
            end

            def take_comparison_screenshot(snapshot)
              snapshot.path.dirname.mkpath
              FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
            end
          end
        end

        # D4: dual return shape — nil for the new-screenshot path, after
        # side-effecting record_new_screenshot into the registry.
        test "#build_screenshot_assertion returns nil and records a new screenshot when no baseline exists" do
          # ScreenshoterStub resolves "c_<digits>" to the c.png fixture.
          name = "c_#{Time.now.nsec}"

          Vcs.stub(:checkout_vcs, false) do
            assertion = ScreenshotMatcher.new(name).build_screenshot_assertion

            assert_nil assertion
            assert_includes CapybaraScreenshotDiff.new_screenshots, name
            assert_predicate CapybaraScreenshotDiff::SnapManager.path_for(name).path, :exist?,
              "the screenshot is still captured on the new-screenshot path"
          end
        end

        # D4: the other return shape — a fully wired ScreenshotAssertion.
        test "#build_screenshot_assertion returns an assertion with compare and caller when a baseline exists" do
          Vcs.stub(:checkout_vcs, true) do
            snap = create_snapshot_for(:a, :c)

            assertion = ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion

            assert_instance_of CapybaraScreenshotDiff::ScreenshotAssertion, assertion
            assert_equal snap.full_name, assertion.name
            assert_kind_of Array, assertion.caller
            assert_match(/screenshot_matcher_test\.rb/, assertion.caller.first)
            assert_equal snap.path, assertion.compare.image_path
            assert_equal snap.base_path, assertion.compare.base_image_path
          end
        end

        # D1: the one-hash-carved-into-two option split. Stability/wait/crop
        # are deleted into capture options; whatever is left over becomes the
        # comparison options.
        test "#build_screenshot_assertion splits capture options from comparison options" do
          calls = []

          Vcs.stub(:checkout_vcs, true) do
            Capybara::Screenshot::Diff.stub(:screenshoter, recording_screenshoter(calls)) do
              snap = create_snapshot_for(:a, :c)

              ScreenshotMatcher.new(snap.full_name, tolerance: 0.03, wait: 5).build_screenshot_assertion
            end
          end

          assert_equal 1, calls.size
          capture_options, comparison_options = calls.first

          assert_equal 5, capture_options[:wait]
          assert_nil capture_options[:stability_time_limit]
          assert_includes capture_options, :crop
          assert_includes capture_options, :screenshot_format

          assert_equal 0.03, comparison_options[:tolerance]
          assert_not_includes comparison_options, :wait, "wait must be carved out of comparison options"
          assert_not_includes comparison_options, :stability_time_limit
          assert_not_includes comparison_options, :crop
        end

        # D1 (fixed): the split is a pure partition — the input hash survives
        # untouched. The frozen input would raise FrozenError under the old
        # delete-based carve.
        test "#extract_capture_and_comparison_options does not mutate the input options" do
          matcher = ScreenshotMatcher.new("a")
          options = {tolerance: 0.03, wait: 5, crop: [0, 0, 2, 2], stability_time_limit: 1}.freeze

          capture_options, comparison_options = matcher.send(:extract_capture_and_comparison_options, options)

          assert_equal 5, capture_options[:wait]
          assert_not_includes comparison_options, :wait
          assert_equal({tolerance: 0.03, wait: 5, crop: [0, 0, 2, 2], stability_time_limit: 1}, options)
        end

        # D2: screenshoter selection is by hash-key presence — no
        # :stability_time_limit means the configured plain screenshoter.
        test "#build_screenshot_assertion uses the configured screenshoter without stability_time_limit" do
          calls = []

          Vcs.stub(:checkout_vcs, true) do
            Capybara::Screenshot::Diff.stub(:screenshoter, recording_screenshoter(calls)) do
              snap = create_snapshot_for(:a, :c)
              ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion
            end
          end

          assert_equal 1, calls.size, "the configured plain screenshoter must take the shot"
        end

        # D2: presence of :stability_time_limit switches to StableScreenshoter.
        test "#build_screenshot_assertion uses StableScreenshoter when stability_time_limit is present" do
          stable_calls = []
          fake_stable = Object.new
          def fake_stable.take_comparison_screenshot(snapshot)
            snapshot.path.dirname.mkpath
            FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
          end

          Vcs.stub(:checkout_vcs, true) do
            SnapDiff::StableScreenshoter.stub(:new, lambda { |capture_options, comparison_options|
              stable_calls << [capture_options, comparison_options]
              fake_stable
            }) do
              snap = create_snapshot_for(:a, :c)
              ScreenshotMatcher.new(snap.full_name, stability_time_limit: 0.1, wait: 1).build_screenshot_assertion
            end
          end

          assert_equal 1, stable_calls.size
          assert_equal 0.1, stable_calls.first.first[:stability_time_limit]
        end

        # The raise-only window-size guard (relocated in the redesign into
        # Capture::Viewport#prepare!): wrong window size fails fast, before
        # any capture.
        test "#build_screenshot_assertion raises WindowSizeMismatchError when the window size is wrong" do
          SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, true) do
            SnapDiff::BrowserHelpers.stub(:selenium?, false) do
              assert_raises(CapybaraScreenshotDiff::WindowSizeMismatchError) do
                ScreenshotMatcher.new("matcher_window_size").build_screenshot_assertion
              end
            end
          end
        end

        # Same guard on the compare-free #capture path.
        test "#capture raises WindowSizeMismatchError when the window size is wrong" do
          SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, true) do
            SnapDiff::BrowserHelpers.stub(:selenium?, false) do
              assert_raises(CapybaraScreenshotDiff::WindowSizeMismatchError) do
                ScreenshotMatcher.new("matcher_window_size").capture
              end
            end
          end
        end

        # Pins the viewport-preparation cadence the Capture::Viewport seam must
        # preserve: the window-size check runs exactly once per capture, before
        # the screenshoter — never re-run per stability retry.
        test "window size is checked exactly once per capture even when stability retries happen" do
          checks = 0
          fake_stable = Object.new
          def fake_stable.take_comparison_screenshot(snapshot)
            # Simulates a stability loop that needed several attempts; nothing
            # here may trigger another window-size check.
            2.times { snapshot.next_attempt_path! }
            snapshot.path.dirname.mkpath
            FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
          end

          SnapDiff::BrowserHelpers.stub(:window_size_is_wrong?, proc { |_expected|
            checks += 1
            false
          }) do
            Vcs.stub(:checkout_vcs, true) do
              SnapDiff::StableScreenshoter.stub(:new, ->(*, **) { fake_stable }) do
                snap = create_snapshot_for(:a, :c)
                ScreenshotMatcher.new(snap.full_name, stability_time_limit: 0.1, wait: 1).build_screenshot_assertion
              end
            end
          end

          assert_equal 1, checks
        end

        # #capture is the compare-free path: file written, no assertion built,
        # nothing recorded in the registry.
        test "#capture writes the screenshot without touching the registry" do
          # ScreenshoterStub resolves "b_<digits>" to the b.png fixture.
          name = "b_#{Time.now.nsec}"

          Vcs.stub(:checkout_vcs, true) do
            ScreenshotMatcher.new(name).capture

            assert_predicate CapybaraScreenshotDiff::SnapManager.path_for(name).path, :exist?
            assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?
            assert_empty CapybaraScreenshotDiff.new_screenshots
          end
        end
      end
    end
  end
end
