# frozen_string_literal: true

require "capybara/rspec"

require "capybara_screenshot_diff/rspec"
require "support/stub_test_methods"

unless defined?(SCREEN_SIZE)
  require "test_helper"
  require "support/setup_capybara_drivers"
end

RSpec.describe "capybara_screenshot_diff/rspec", type: :feature do
  before do
    Capybara.current_driver = Capybara.javascript_driver
    Capybara.page.current_window.resize_to(*SCREEN_SIZE)
    Capybara::Screenshot.window_size = SCREEN_SIZE

    Capybara::Screenshot.save_path = "doc/screenshots"
    Capybara::Screenshot.root = Rails.root / "../test/fixtures/app"
    Capybara::Screenshot.add_os_path = true
    Capybara::Screenshot.add_driver_path = true
    Capybara::Screenshot::Diff.driver = ENV.fetch("SCREENSHOT_DRIVER", "chunky_png").to_sym
  end

  it "should include CapybaraScreenshotDiff in rspec" do
    expect(self.class.ancestors).to include Capybara::Screenshot::Diff::TestMethods
  end

  it "visits and compare screenshot on teardown" do
    visit "/"
    screenshot "index"
  end

  it "use custom matcher" do
    visit "/"

    expect(page).to match_screenshot("index", skip_stack_frames: 1, driver: :chunky_png)
  end

  it "does not conflicts with rspec methods" do
    expect { raise StandardError }.to raise_error(StandardError)
  end
end
