# frozen_string_literal: true

require "minitest"
require "capybara_screenshot_diff"

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
          if ::Capybara::Screenshot.active? && ::Capybara::Screenshot::Diff.fail_on_difference && @test_screenshots.present?
            errors = validate_screenshots!(@test_screenshots)
            failures << ::Minitest::Assertion.new(errors.join("\n\n")) if errors
          end
        end
      end
    end
  end
end
