# frozen_string_literal: true

require "capybara/rspec"

require "capybara/screenshot/diff"
require "capybara_screenshot_diff/rspec"
require "support/stub_test_methods"

RSpec.describe "capybara_screenshot_diff/rspec", type: :feature do
  before do
    Capybara.current_driver = Capybara.javascript_driver
    Capybara.page.current_window.resize_to(*SCREEN_SIZE)
    Capybara::Screenshot.window_size = SCREEN_SIZE

    browser = BROWSERS.fetch(Capybara.current_driver, "chrome")
    Capybara::Screenshot.save_path = "test/fixtures/app/doc/screenshots/#{browser}"
    Capybara::Screenshot::Diff.driver = ENV.fetch("SCREENSHOT_DRIVER", "chunky_png").to_sym
  end

  it "should include CapybaraScreenshotDiff in rspec" do
    expect(self.class.ancestors).to include Capybara::Screenshot::Diff::TestMethods
  end

  it "visits and compare screenshot on teardown" do
    visit "/"
    screenshot "index"
  end
end
