# frozen_string_literal: true

require "capybara_screenshot_diff/screenshot_namer"

module Capybara
  module Screenshot
    module Diff
      # Provides methods for managing screenshot naming conventions
      # with support for grouping and sectioning for better organization.
      module ScreenshotNamerDSL
        # Sets the current section name for screenshots
        # @param name [String] Section name
        # @return [void]
        def screenshot_section(name)
          screenshot_namer.section = name
        end

        # Sets the current group name for screenshots
        # @param name [String] Group name
        # @return [void]
        def screenshot_group(name)
          screenshot_namer.group = name
        end

        private

        # Access the current screenshot namer instance
        # @return [CapybaraScreenshotDiff::ScreenshotNamer]
        def screenshot_namer
          CapybaraScreenshotDiff.screenshot_namer
        end
      end
    end
  end
end
