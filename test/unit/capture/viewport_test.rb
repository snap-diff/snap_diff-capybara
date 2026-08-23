# frozen_string_literal: true

require "test_helper"
require "snap_diff"

module SnapDiff
  module Capture
    # Direct coverage for the per-capture viewport preparation seam
    # (5.5-lite item 6): a raise-only window-size guard.
    class ViewportTest < ActiveSupport::TestCase
      test "prepare! is a no-op when the window size matches" do
        BrowserHelpers.stub(:window_size_is_wrong?, false) do
          assert_nil Viewport.prepare!([800, 600])
        end
      end

      test "prepare! raises WindowSizeMismatchError when the window size is wrong" do
        BrowserHelpers.stub(:window_size_is_wrong?, true) do
          BrowserHelpers.stub(:selenium?, false) do
            error = assert_raises(SnapDiff::WindowSizeMismatchError) do
              Viewport.prepare!([800, 600])
            end
            assert_includes error.message, "[800, 600]"
            assert_includes error.message, "Actual: unknown"
          end
        end
      end

      # The selenium arm of the ternary was never taken -- the test above
      # stubs selenium? to false, and nothing else calls prepare! -- so the
      # whole `session.driver.browser.manage.window.size` chain (the only
      # reason the message is ever useful) was unexecuted. Under selenium the
      # message must name the size the browser ACTUALLY has.
      test "prepare! reports the real window size when the driver is selenium" do
        window = Struct.new(:size).new("(width: 1024, height: 768)")
        manage = Struct.new(:window).new(window)
        browser = Struct.new(:manage).new(manage)
        driver = Struct.new(:browser).new(browser)
        session = Struct.new(:driver).new(driver)

        BrowserHelpers.stub(:window_size_is_wrong?, true) do
          BrowserHelpers.stub(:selenium?, true) do
            BrowserHelpers.stub(:session, session) do
              error = assert_raises(SnapDiff::WindowSizeMismatchError) do
                Viewport.prepare!([800, 600])
              end

              assert_includes error.message, "Expected: [800, 600]"
              assert_includes error.message, "Actual: (width: 1024, height: 768)"
            end
          end
        end
      end
    end
  end
end
