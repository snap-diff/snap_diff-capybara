# frozen_string_literal: true

require_relative "os"

module Capybara
  module Screenshot
    module Diff
      module Stabilization
        include Os

        IMAGE_WAIT_SCRIPT = <<-JS.strip_heredoc.freeze
          function pending_image() {
            var images = document.images;
            for (var i = 0; i < images.length; i++) {
              if (!images[i].complete) {
                  return images[i].src;
              }
            }
            return false;
          }()
        JS

        HIDE_CARET_SCRIPT = <<~JS
          if (!document.getElementById('csdHideCaretStyle')) {
            let style = document.createElement('style');
            style.setAttribute('id', 'csdHideCaretStyle');
            document.head.appendChild(style);
            let styleSheet = style.sheet;
            styleSheet.insertRule("* { caret-color: transparent !important; }", 0);
          }
        JS

        def take_stable_screenshot(comparison, stability_time_limit:, wait:)
          previous_file_name = comparison.old_file_name
          screenshot_started_at = last_image_change_at = Time.now
          clean_stabilization_images(comparison.new_file_name)

          1.step do |i|
            take_right_size_screenshot(comparison)
            if comparison.quick_equal?
              clean_stabilization_images(comparison.new_file_name)
              break
            end
            comparison.reset

            if previous_file_name
              stabilization_comparison = make_stabilization_comparison_from(
                comparison,
                comparison.new_file_name,
                previous_file_name
              )
              if stabilization_comparison.quick_equal?
                if (Time.now - last_image_change_at) > stability_time_limit
                  clean_stabilization_images(comparison.new_file_name)
                  break
                end
                next
              else
                last_image_change_at = Time.now
              end
            end

            previous_file_name = build_snapshot_version_file_name(
              comparison,
              i,
              screenshot_started_at,
              stabilization_comparison
            )

            FileUtils.mv(comparison.new_file_name, previous_file_name)

            check_max_wait_time(
              comparison,
              screenshot_started_at,
              max_wait_time: max_wait_time(comparison.shift_distance_limit, wait)
            )
          end
        end

        def notice_how_to_avoid_this
          unless @_csd_retina_warned
            warn "Halving retina screenshot.  " \
                'You should add "force-device-scale-factor=1" to your Chrome chromeOptions args.'
            @_csd_retina_warned = true
          end
        end

        private

        def build_snapshot_version_file_name(comparison, iteration, screenshot_started_at, stabilization_comparison)
          "#{comparison.new_file_name.chomp(".png")}" \
                "_x#{format("%02i", iteration)}_#{(Time.now - screenshot_started_at).round(1)}s" \
                "_#{stabilization_comparison.difference_region&.to_s&.gsub(", ", "_") || :initial}.png" \
                "#{ImageCompare::TMP_FILE_SUFFIX}"
        end

        def make_stabilization_comparison_from(comparison, new_file_name, previous_file_name)
          ImageCompare.new(new_file_name, previous_file_name, comparison.driver_options)
        end

        def reduce_retina_image_size(file_name, driver)
          return if !ON_MAC || !selenium? || !Capybara::Screenshot.window_size

          expected_image_width = Capybara::Screenshot.window_size[0]
          saved_image = driver.from_file(file_name)
          return if driver.width_for(saved_image) < expected_image_width * 2

          notice_how_to_avoid_this

          new_height = expected_image_width * driver.height_for(saved_image) / driver.width_for(saved_image)
          resized_image = driver.resize_image_to(saved_image, expected_image_width, new_height)

          Dir.mktmpdir do |dir|
            resized_image_file = "#{dir}/resized.png"
            driver.save_image_to(resized_image, resized_image_file)
            FileUtils.mv(resized_image_file, file_name)
          end
        end

        def stabilization_images(base_file)
          Dir["#{base_file.chomp(".png")}_x*.png#{ImageCompare::TMP_FILE_SUFFIX}"].sort
        end

        def clean_stabilization_images(base_file)
          FileUtils.rm stabilization_images(base_file)
        end

        def prepare_page_for_screenshot(timeout:)
          assert_images_loaded(timeout: timeout)
          if Capybara::Screenshot.blur_active_element
            active_element = execute_script(<<-JS)
              ae = document.activeElement;
              if (ae.nodeName === "INPUT" || ae.nodeName === "TEXTAREA") {
                  ae.blur();
                  return ae;
              }
              return null;
            JS
            blurred_input = page.driver.send :unwrap_script_result, active_element
          end
          execute_script(HIDE_CARET_SCRIPT) if Capybara::Screenshot.hide_caret
          blurred_input
        end

        def take_right_size_screenshot(comparison)
          save_screenshot(comparison.new_file_name)

          # TODO(uwe): Remove when chromedriver takes right size screenshots
          reduce_retina_image_size(comparison.new_file_name, comparison.driver)
          # ODOT
        end

        def check_max_wait_time(comparison, screenshot_started_at, max_wait_time:)
          return if (Time.now - screenshot_started_at) < max_wait_time

          annotate_stabilization_images(comparison)
          # FIXME(uwe): Change to store the failure and only report if the test succeeds functionally.
          fail("Could not get stable screenshot within #{max_wait_time}s\n" \
                    "#{stabilization_images(comparison.new_file_name).join("\n")}")
        end

        def annotate_stabilization_images(comparison)
          previous_file = comparison.old_file_name
          stabilization_images(comparison.new_file_name).each do |file_name|
            if File.exist? previous_file
              stabilization_comparison = make_stabilization_comparison_from(
                comparison,
                file_name,
                previous_file
              )
              if stabilization_comparison.different?
                FileUtils.mv stabilization_comparison.annotated_new_file_name, file_name
              end
              FileUtils.rm stabilization_comparison.annotated_old_file_name
            end
            previous_file = file_name
          end
        end

        def max_wait_time(shift_distance_limit, wait)
          shift_factor = shift_distance_limit ? (shift_distance_limit * 2 + 1) ^ 2 : 1
          wait * shift_factor
        end

        def assert_images_loaded(timeout:)
          return unless respond_to? :evaluate_script

          start = Time.now
          loop do
            pending_image = evaluate_script IMAGE_WAIT_SCRIPT
            break unless pending_image

            assert(
              (Time.now - start) < timeout,
              "Images not loaded after #{timeout}s: #{pending_image.inspect}"
            )

            sleep 0.1
          end
        end
      end
    end
  end
end
