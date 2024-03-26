# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

module Capybara
  module Screenshot
    class ScreenshoterTest < ActionDispatch::IntegrationTest
      include Diff::TestMethods
      include Diff::TestMethodsStub

      test "#take_screenshot without wait skips image loading" do
        screenshoter = Screenshoter.new({wait: nil}, Diff::Drivers.for)

        mock = ::Minitest::Mock.new
        mock.expect(:save_screenshot, true) { |path| path.include?("01_a.png") }

        BrowserHelpers.stub(:session, mock) do
          screenshoter.stub(:process_screenshot, true) do
            screenshoter.take_screenshot(Pathname.new("tmp/01_a.png"))
          end
        end

        mock.verify
      end

      test "#prepare_page_for_screenshot without wait skips image loading" do
        Screenshoter.new({wait: nil}, Diff::Drivers.for).prepare_page_for_screenshot(timeout: nil)
      end
    end
  end
end
