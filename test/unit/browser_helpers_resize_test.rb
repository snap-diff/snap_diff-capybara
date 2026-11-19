# frozen_string_literal: true

require "test_helper"
require "snap_diff"
require "capybara/cuprite"

module SnapDiff
  class BrowserHelpersResizeTest < ActiveSupport::TestCase
    class ResizableDriver
      attr_reader :resizes

      def initialize
        @resizes = []
      end

      def resize(width, height)
        @resizes << [width, height]
      end
    end

    # Cuprite 0.20: Driver#resize still exists, and warns when called.
    class DeprecatedResizeCuprite < Capybara::Cuprite::Driver
      attr_reader :resizes

      def initialize
        @resizes = []
      end

      def resize(width, height)
        @resizes << [width, height]
      end
    end

    # Cuprite 0.21: Driver#resize is gone.
    class ResizeRemovedCuprite < Capybara::Cuprite::Driver
      def initialize
      end

      undef_method :resize if method_defined?(:resize)
    end

    class SeleniumDriver < Capybara::Selenium::Driver
      attr_reader :browser

      def initialize(window)
        manage = Struct.new(:window).new(window)
        @browser = Struct.new(:manage).new(manage)
      end
    end

    class Window
      attr_reader :size

      def resize_to(width, height)
        @size = [width, height]
      end
    end

    # A session whose current_window raises, as Capybara's does for a driver
    # with no window support.
    class WindowlessSession
      attr_reader :driver

      def initialize(driver)
        @driver = driver
      end

      def current_window
        raise Capybara::NotSupportedByDriverError, "current_window"
      end
    end

    def resize_with(session)
      BrowserHelpers.stub(:session, session) do
        BrowserHelpers.resize_to([1024, 768])
      end
    end

    def session_with(driver, window = Window.new)
      Struct.new(:driver, :current_window).new(driver, window)
    end

    test "resize_to sizes Cuprite through Capybara's window API, not the deprecated Driver#resize" do
      driver = DeprecatedResizeCuprite.new
      window = Window.new

      resize_with(session_with(driver, window))

      assert_equal [1024, 768], window.size
      assert_empty driver.resizes
    end

    test "resize_to still sizes a Cuprite that has dropped Driver#resize" do
      driver = ResizeRemovedCuprite.new
      window = Window.new
      refute_respond_to driver, :resize

      resize_with(session_with(driver, window))

      assert_equal [1024, 768], window.size
    end

    test "resize_to sizes a non-Cuprite driver that exposes resize through that method" do
      driver = ResizableDriver.new

      resize_with(WindowlessSession.new(driver))

      assert_equal [[1024, 768]], driver.resizes
    end

    test "resize_to sizes Selenium through the browser's window manager" do
      window = Window.new

      resize_with(WindowlessSession.new(SeleniumDriver.new(window)))

      assert_equal [1024, 768], window.size
    end

    test "resize_to leaves a driver with no windows alone" do
      assert_nothing_raised do
        resize_with(WindowlessSession.new(Capybara::RackTest::Driver.allocate))
      end
    end

    test "cuprite? is true only for a Cuprite driver" do
      assert BrowserHelpers.stub(:session, session_with(ResizeRemovedCuprite.new)) { BrowserHelpers.cuprite? }
      refute BrowserHelpers.stub(:session, session_with(ResizableDriver.new)) { BrowserHelpers.cuprite? }
    end
  end
end
