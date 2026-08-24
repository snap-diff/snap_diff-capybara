# frozen_string_literal: true

# Bundler.require entry point for `gem "snap_diff-capybara"`: Bundler
# requires the gem's own name, and its dash->slash fallback ("snap_diff/
# capybara") misses too, so without this file a Rails user gets a silent
# no-op and a confusing NameError later. The sibling
# capybara-screenshot-diff.rb is the same door under the v1 gem name and
# forwards here.
#
# Everything below therefore loads for EVERY consumer, RSpec and Cucumber
# users included, so nothing outside the gem's declared runtime dependencies
# may be hard-required. minitest is not one of them -- the gemspec declares
# capybara only -- and requiring it here killed an RSpec-only bundle at boot
# with `cannot load such file -- minitest`, from a gem that ships a
# first-class RSpec integration.
#
# So: load the gem, then feature-detect minitest. Present is the documented
# zero-require Rails path and still activates the assertions. Absent gets a
# line saying so -- a gem that loads and then does nothing, silently, is its
# own bug report.
# This IS the canonical door, and it loads the v1 umbrella below -- so claim
# the process before that require, or every canonical user is told to
# migrate off an API they never touched.
require "snap_diff/deprecation"
SnapDiff::Deprecation.canonical_entry_point!

require "capybara_screenshot_diff"

begin
  require "minitest"
rescue LoadError
  warn "[snap_diff] minitest is not in this bundle, so `Bundler.require` activated no test-framework " \
    "integration. Require the one you use -- `require \"snap_diff/integrations/rspec\"` or " \
    "`require \"snap_diff/integrations/cucumber\"` -- and set `require: false` on the gem in your " \
    "Gemfile to silence this. See docs/framework-setup.md."
end

require "capybara_screenshot_diff/minitest" if defined?(::Minitest)
