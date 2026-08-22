# frozen_string_literal: true

require "capybara/screenshot/diff/drivers"
require "snap_diff/driver"

# BaseDriver was dissolved into the SnapDiff::Driver mixin (ADR-004 v2
# step 4). Alias kept so existing requires of this file keep resolving;
# note it is now a module — `class MyDriver < BaseDriver` becomes
# `include SnapDiff::Driver`.
Capybara::Screenshot::Diff::Drivers::BaseDriver = SnapDiff::Driver
