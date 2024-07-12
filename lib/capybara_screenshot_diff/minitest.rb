# frozen_string_literal: true

require "minitest"

module Capybara::Screenshot::Diff
  ASSERTION = ::Minitest::Assertion unless defined?(::Capybara::Screenshot::Diff::ASSERTION)
end

module CapybaraScreenshotDiff
  module Minitest
    module Assertions
      def self.included(klass)
        klass.include ::Capybara::Screenshot::Diff::TestMethods

        klass.setup do
          if ::Capybara::Screenshot.window_size
            ::Capybara::Screenshot::BrowserHelpers.resize_to(::Capybara::Screenshot.window_size)
          end
        end

        klass.teardown do
          if ::Capybara::Screenshot.active? && @test_screenshots.present?
            begin
              track_failures(@test_screenshots)
            ensure
              @test_screenshots.clear
            end
          end
        end
      end

      private

      EMPTY_LINE = "\n\n"

      def track_failures(screenshots)
        test_screenshot_errors = screenshots.map do |caller, name, compare|
          assert_image_not_changed(caller, name, compare)
        end

        test_screenshot_errors.compact!

        unless test_screenshot_errors.empty?
          error = ::Capybara::Screenshot::Diff::ASSERTION.new(test_screenshot_errors.join(EMPTY_LINE))
          error.set_backtrace([])

          if ::Capybara::Screenshot::Diff.fail_on_difference
            if is_a?(::Minitest::Runnable)
              failures << error
            else
              raise error
            end
          end
        end
      end
    end
  end
end
