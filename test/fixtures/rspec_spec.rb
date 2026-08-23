# frozen_string_literal: true

require "capybara/rspec"

require "snap_diff/integrations/rspec"
require "support/stub_test_methods"

unless defined?(SCREEN_SIZE)
  require "test_helper"
  require "support/setup_capybara_drivers"
end

RSpec.describe "capybara_screenshot_diff/rspec", type: :feature do
  before do
    Capybara.current_driver = Capybara.javascript_driver
    Capybara.page.current_window.resize_to(*SCREEN_SIZE)
    SnapDiff.config.window_size = SCREEN_SIZE

    SnapDiff.config.save_path = "doc/screenshots"
    SnapDiff.config.root = Rails.root / "../test/fixtures/app"
    SnapDiff.config.add_os_path = true
    SnapDiff.config.add_driver_path = true
    SnapDiff.config.tolerance = 0.5
  end

  it "should include SnapDiff::DSL in rspec" do
    expect(self.class.ancestors).to include SnapDiff::DSL
  end

  it "visits and compare screenshot on teardown" do
    visit "/"
    screenshot "index"
  end

  it "use custom matcher" do
    visit "/"

    expect(page).to match_screenshot("index", skip_stack_frames: 1)
  end

  it "does not conflicts with rspec methods" do
    expect { raise StandardError }.to raise_error(StandardError)
  end

  it "marks the example pending when a new screenshot has no baseline and pending_if_new is enabled" do
    name = "pending-if-new-example"
    allow(SnapDiff.config).to receive(:pending_if_new).and_return(true)
    visit "/"
    screenshot name
  ensure
    FileUtils.rm_f(SnapDiff::SnapManager.snapshot(name).path)
  end
end
