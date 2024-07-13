# frozen_string_literal: true

warn <<~MSG

    DEPRECATED: use 'require "capybara_screenshot_diff/minitest"' instead of 'require "capybara/screenshot/diff"'
        in #{caller(3)&.first}. 
        "capybara/screenshot/diff" is no longer needed and will be removed in the next major release.

MSG

require "capybara_screenshot_diff/minitest"
