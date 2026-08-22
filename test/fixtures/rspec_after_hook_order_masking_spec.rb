# frozen_string_literal: true

require "capybara/rspec"

# Registered BEFORE `capybara_screenshot_diff/rspec` is required below.
# RSpec's `after(:each)` hooks run in REVERSE registration order (the last
# hook registered runs first), so this user hook -- registered first, here
# -- runs AFTER the gem's own `config.after` hook, which is registered next
# when the require below loads. That reproduces the ordering hazard: by the
# time the gem's hook runs (first) and marks the example pending, this hook
# hasn't raised yet; by the time this hook raises (last), the gem has
# already committed to "pending".
RSpec.configure do |config|
  config.after do
    raise "deliberate failure: a config.after hook registered before the gem loaded"
  end
end

require "capybara_screenshot_diff/rspec"
require "support/stub_test_methods"

unless defined?(SCREEN_SIZE)
  # Deliberately does NOT require "test_helper": that pulls in
  # `minitest/autorun`, whose `at_exit` hook hijacks this process's exit
  # code when run standalone (as it is here, from a subprocess). Require
  # only what an RSpec-only run actually needs.
  require "support/setup_rails_app"
  require "support/setup_capybara"
  require "support/setup_capybara_drivers"
end

# Regression fixture for the "gem's pending hook must run after the full
# user after-chain" guard in capybara_screenshot_diff/rspec.rb.
#
# Run via test/integration/rspec_after_hook_order_masking_test.rb, which
# executes this file in a fresh subprocess and asserts the run reports a
# failure (not a pending/skip), even though the example also records a new
# screenshot under `pending_if_new` and never fails on its own.
RSpec.describe "capybara_screenshot_diff/rspec after-hook ordering masking guard", type: :feature do
  before do
    Capybara.current_driver = Capybara.javascript_driver
    Capybara.page.current_window.resize_to(*SCREEN_SIZE)
    Capybara::Screenshot.window_size = SCREEN_SIZE

    Capybara::Screenshot.save_path = "doc/screenshots"
    Capybara::Screenshot.root = Rails.root / "../test/fixtures/app"
    Capybara::Screenshot.add_os_path = true
    Capybara::Screenshot.add_driver_path = true
    Capybara::Screenshot::Diff.driver = ENV.fetch("SCREENSHOT_DRIVER", "chunky_png").to_sym
    Capybara::Screenshot::Diff.tolerance = 0.5
    # This fixture runs standalone in its own subprocess (no
    # ActiveSupport::TestCase setup forcing this off), and CI sets $CI,
    # which flips the default on and would raise before we ever get here.
    Capybara::Screenshot::Diff.fail_if_new = false
  end

  it "keeps a real after-hook failure failing even when a new screenshot is pending" do
    name = "pending-masking-after-hook-order"
    allow(Capybara::Screenshot::Diff).to receive(:pending_if_new).and_return(true)
    visit "/"
    screenshot name
  ensure
    FileUtils.rm_f(SnapDiff::SnapManager.snapshot(name).path)
  end
end
