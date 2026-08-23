# frozen_string_literal: true

# Entry point for the `capybara-screenshot-diff` GEM NAME.
#
# This is not part of the v1 namespace that 2.1 removed -- it is the file
# Bundler looks for when a Gemfile says `gem "capybara-screenshot-diff"`.
# Bundler.require requires the gem's own name, and its dash->slash fallback
# ("capybara/screenshot/diff") no longer exists, so without this file a Rails
# user gets a silent no-op and a confusing NameError later.
#
# The gem ships under two names with identical content; see
# lib/snap_diff-capybara.rb for the other one.
require "snap_diff/integrations/minitest"
