# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Capybara
  module Screenshot
    class ScreenshoterTest < ActiveSupport::TestCase
      include CapybaraScreenshotDiff::DSL
      include CapybaraScreenshotDiff::DSLStub

      test "#take_screenshot without wait skips image loading" do
        screenshoter = Screenshoter.new({wait: nil}, {driver: :chunky_png})

        mock = ::Minitest::Mock.new
        mock.expect(:save_screenshot, true) { |path| path.include?("01_a.png") }

        BrowserHelpers.stub(:session, mock) do
          screenshoter.stub(:process_screenshot, true) do
            screenshoter.take_screenshot(Pathname.new("tmp/01_a.png"))
          end
        end

        assert mock.verify
      end

      test "#take_screenshot with custom screenshot options" do
        screenshoter = Screenshoter.new(
          {wait: nil, capybara_screenshot_options: {full: true}},
          {driver: :chunky_png}
        )

        mock = ::Minitest::Mock.new
        mock.expect(:save_screenshot, true) { |path, options| path.include?("01_a.png") && options[:full] }

        BrowserHelpers.stub(:session, mock) do
          screenshoter.stub(:process_screenshot, true) do
            screenshoter.take_screenshot(Pathname.new("tmp/01_a.png"))
          end
        end

        assert mock.verify
      end

      test "#prepare_page_for_screenshot without wait does not raise any error" do
        screenshoter = Screenshoter.new({wait: nil}, {driver: :chunky_png})

        assert_nil screenshoter.prepare_page_for_screenshot(timeout: nil) # does not raise an error
      end

      test "#resize_if_needed halves a non-square retina screenshot to the expected window size via VipsDriver" do
        screenshoter = Screenshoter.new({}, {driver: :vips})
        retina_image = Vips::Image.black(2560, 1600) # 2x window size, non-square

        resized = Screenshot.stub(:window_size, [1280, 1024]) do
          screenshoter.send(:resize_if_needed, retina_image)
        end

        assert_equal [1280, 800], screenshoter.driver.dimension(resized)
      end
    end
  end
end
