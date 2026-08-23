# frozen_string_literal: true

# Legacy (v1-documented) entry point: like every other legacy entry, it must
# load the legacy surface too -- requiring only the canonical integration
# left CapybaraScreenshotDiff half-present (module defined, but .verify /
# .reset / .reporters / ... gone) for v1 users of this path.
require "capybara_screenshot_diff/cucumber"
