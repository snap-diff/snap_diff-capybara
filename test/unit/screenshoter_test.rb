# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ScreenshoterTest < ActiveSupport::TestCase
  include SnapDiff::DSL
  include DSLStub

  test "#take_screenshot without wait skips image loading" do
    screenshoter = SnapDiff::Screenshoter.new({wait: nil}, {driver: :chunky_png})

    mock = ::Minitest::Mock.new
    mock.expect(:save_screenshot, true) { |path| path.include?("01_a.png") }

    SnapDiff::BrowserHelpers.stub(:session, mock) do
      screenshoter.stub(:process_screenshot, true) do
        screenshoter.take_screenshot(Pathname.new("tmp/01_a.png"))
      end
    end

    assert mock.verify
  end

  test "#take_screenshot with custom screenshot options" do
    screenshoter = SnapDiff::Screenshoter.new(
      {wait: nil, capybara_screenshot_options: {full: true}},
      {driver: :chunky_png}
    )

    mock = ::Minitest::Mock.new
    mock.expect(:save_screenshot, true) { |path, options| path.include?("01_a.png") && options[:full] }

    SnapDiff::BrowserHelpers.stub(:session, mock) do
      screenshoter.stub(:process_screenshot, true) do
        screenshoter.take_screenshot(Pathname.new("tmp/01_a.png"))
      end
    end

    assert mock.verify
  end

  test "#prepare_page_for_screenshot without wait does not raise any error" do
    screenshoter = SnapDiff::Screenshoter.new({wait: nil}, {driver: :chunky_png})

    assert_nil screenshoter.prepare_page_for_screenshot(timeout: nil) # does not raise an error
  end

  test "#resize_if_needed halves a non-square retina screenshot to the expected window size via VipsDriver" do
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
    screenshoter = SnapDiff::Screenshoter.new({}, {driver: :vips})
    retina_image = Vips::Image.black(2560, 1600) # 2x window size, non-square

    resized = SnapDiff.config.stub(:window_size, [1280, 1024]) do
      screenshoter.send(:resize_if_needed, retina_image)
    end

    assert_equal [1280, 800], screenshoter.driver.dimension(resized)
  end
end
