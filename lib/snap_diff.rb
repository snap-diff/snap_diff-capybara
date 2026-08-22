# frozen_string_literal: true

require "capybara_screenshot_diff"

# Forward-looking namespace for the gem, per ADR-004.
#
# These are pure additive aliases onto the existing
# +Capybara::Screenshot::Diff+ API — no behavior changes, no deprecation
# warnings. See ADR-004 for the full migration plan.
module SnapDiff
  Comparison = Capybara::Screenshot::Diff::ImageCompare

  def self.compare(...)
    Capybara::Screenshot::Diff.compare(...)
  end

  def self.start(&block)
    Capybara::Screenshot::Diff.configure(&block)
  end
end
