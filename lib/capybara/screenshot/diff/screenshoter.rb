# frozen_string_literal: true

require_relative "os"
require_relative "browser_helpers"

module Capybara
  module Screenshot
    class Screenshoter
      attr_reader :capture_options, :driver

      def initialize(capture_options, driver)
        @capture_options = capture_options
        @driver = driver
      end

      def crop
        @capture_options[:crop]
      end

      def wait
        @capture_options[:wait]
      end

      def screenshot_format
        @capture_options[:screenshot_format] || "png"
      end

      def capybara_screenshot_options
        @capture_options[:capybara_screenshot_options] || {}
      end

      # Try to get screenshot from browser.
      # On `stability_time_limit` it checks that page stop updating by comparison several screenshot attempts
      # On reaching `wait` limit then it has been failed. On failing we annotate screenshot attempts to help to debug
      def take_comparison_screenshot(snapshot)
        capture_screenshot_at(snapshot)
        snapshot.cleanup_attempts
      end

      PNG_EXTENSION = ".png"

      def take_screenshot(screenshot_path)
        blurred_input = prepare_page_for_screenshot(timeout: wait)

        # Take browser screenshot and save
        save_and_process_screenshot(screenshot_path)

        blurred_input&.click
      end

      def process_screenshot(stored_path, screenshot_path)
        screenshot_image = driver.from_file(stored_path)

        # TODO(uwe): Remove when chromedriver takes right size screenshots
        # TODO: Adds tests when this case is true
        screenshot_image = resize_if_needed(screenshot_image) if selenium_with_retina_screen?
        # ODOT

        screenshot_image = driver.crop(crop, screenshot_image) if crop

        driver.save_image_to(screenshot_image, screenshot_path)
      end

      def notice_how_to_avoid_this
        unless defined?(@_csd_retina_warned)
          warn "Halving retina screenshot.  " \
                 'You should add "force-device-scale-factor=1" to your Chrome chromeOptions args.'
          @_csd_retina_warned = true
        end
      end

      def prepare_page_for_screenshot(timeout:)
        wait_images_loaded(timeout: timeout) if timeout

        blurred_input = BrowserHelpers.blur_from_focused_element if Screenshot.blur_active_element

        if Screenshot.hide_caret
          BrowserHelpers.hide_caret
        end

        blurred_input
      end

      def wait_images_loaded(timeout:)
        return unless timeout

        deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          Capybara.default_max_wait_time
          pending_image = BrowserHelpers.pending_image_to_load
          break unless pending_image

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline_at
            raise CapybaraScreenshotDiff::ExpectationNotMet, "Images have not been loaded after #{timeout}s: #{pending_image.inspect}"
          end

          sleep 0.025
        end
      end

      private

      def save_and_process_screenshot(screenshot_path)
        tmpfile = Tempfile.new([screenshot_path.basename.to_s, PNG_EXTENSION])
        BrowserHelpers.session.save_screenshot(tmpfile.path, **capybara_screenshot_options)
        # Load saved screenshot and pre-process it
        process_screenshot(tmpfile.path, screenshot_path)
      ensure
        File.unlink(tmpfile) if tmpfile
      end

      def capture_screenshot_at(snapshot)
        take_screenshot(snapshot.next_attempt_path)
        snapshot.commit_last_attempt
      end

      def resize_if_needed(saved_image)
        expected_image_width = Screenshot.window_size[0]
        return saved_image if driver.width_for(saved_image) < expected_image_width * 2

        notice_how_to_avoid_this

        new_height = expected_image_width * driver.height_for(saved_image) / driver.width_for(saved_image)
        driver.resize_image_to(saved_image, expected_image_width, new_height)
      end

      def selenium_with_retina_screen?
        Os::ON_MAC && BrowserHelpers.selenium? && Screenshot.window_size
      end
    end
  end
end
