# frozen_string_literal: true

require "capybara/rspec"

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

# Regression fixture for the "never mask a real failure with a pending
# marker" guard in capybara_screenshot_diff/rspec.rb's `config.after` hook
# (`example.exception.nil? && ...`).
#
# Run via test/integration/rspec_pending_masking_test.rb, which executes
# this file in a fresh subprocess and asserts the run reports a failure
# (not a pending/skip), even though the example also records a new
# screenshot under `pending_if_new`.
RSpec.describe "capybara_screenshot_diff/rspec pending_if_new masking guard", type: :feature do
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

  it "keeps a genuine failure failing even when a new screenshot is pending" do
    name = "pending-masking-real-failure"
    allow(Capybara::Screenshot::Diff).to receive(:pending_if_new).and_return(true)
    visit "/"
    screenshot name

    raise "deliberate failure: pending_if_new must never mask this"
  ensure
    FileUtils.rm_f(CapybaraScreenshotDiff::SnapManager.snapshot(name).path)
  end
end
