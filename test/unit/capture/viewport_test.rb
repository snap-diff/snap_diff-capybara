# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module SnapDiff
  module Capture
    # Direct coverage for the per-capture viewport preparation seam
    # (5.5-lite item 6): raise-only window-size guard, plus the anchor:
    # parameter reserved for v3 scroll preservation.
    class ViewportTest < ActiveSupport::TestCase
      test "prepare! is a no-op when the window size matches" do
        BrowserHelpers.stub(:window_size_is_wrong?, false) do
          assert_nil Viewport.prepare!([800, 600])
        end
      end

      test "prepare! raises WindowSizeMismatchError when the window size is wrong" do
        BrowserHelpers.stub(:window_size_is_wrong?, true) do
          BrowserHelpers.stub(:selenium?, false) do
            error = assert_raises(CapybaraScreenshotDiff::WindowSizeMismatchError) do
              Viewport.prepare!([800, 600])
            end
            assert_includes error.message, "[800, 600]"
          end
        end
      end

      test "prepare! accepts the v3 anchor seam parameter without acting on it" do
        BrowserHelpers.stub(:window_size_is_wrong?, false) do
          assert_nil Viewport.prepare!([800, 600], anchor: "#some-element")
        end
      end
    end
  end
end
