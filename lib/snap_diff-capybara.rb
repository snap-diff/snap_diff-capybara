# frozen_string_literal: true

# Bundler.require entry point for `gem "snap_diff-capybara"`: Bundler
# requires the gem's own name, and its dash->slash fallback ("snap_diff/
# capybara") misses too, so without this file a Rails user gets a silent
# no-op and a confusing NameError later.
require "snap_diff/integrations/minitest"
