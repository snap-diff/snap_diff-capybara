require 'english'
require 'capybara'
require 'capybara/screenshot/diff/image_compare'
require 'action_controller'
require 'action_dispatch'
require 'active_support/core_ext/string/strip'

# TODO(uwe): Move this code to module Capybara::Screenshot::Diff::TestMethods,
#            and use Module#prepend/include to insert.
# Add the `screenshot` method to ActionDispatch::IntegrationTest
module Capybara
  module Screenshot
    module Diff
      module TestMethods
        ON_WINDOWS = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
        SILENCE_ERRORS = ON_WINDOWS ? '2>nul' : '2>/dev/null'

        def self.prepended(clas)
          clas.extend ClassMethods
        end

        module ClassMethods
          def os_name
            case RbConfig::CONFIG['host_os']
            when /darwin/
              'macos'
            when /mswin|mingw|cygwin/
              'windows'
            when /linux/
              'linux'
            else
              'unknown'
            end
          end

          def macos?
            os_name == 'macos'
          end

          def screenshot_root
            Capybara::Screenshot.screenshot_root ||
              (defined?(Rails.root) && Rails.root) || File.expand_path('.')
          end

          def screenshot_area
            parts = ['doc/screenshots']
            parts << Capybara.default_driver.to_s if Capybara::Screenshot.add_driver_path
            parts << os_name if Capybara::Screenshot.add_os_path
            File.join parts
          end

          def screenshot_area_abs
            "#{screenshot_root}/#{screenshot_area}".freeze
          end
        end

        def initialize(*)
          super
          @screenshot_counter = nil
          @screenshot_group = nil
          @screenshot_section = nil
          @test_screenshot_errors = nil
          @test_screenshots = nil
        end

        def group_parts
          parts = []
          parts << @screenshot_section if @screenshot_section.present?
          parts << @screenshot_group if @screenshot_group.present?
          parts
        end

        def full_name(name)
          File.join group_parts.<<(name).map(&:to_s)
        end

        def screenshot_dir
          File.join [self.class.screenshot_area] + group_parts
        end

        private def current_capybara_driver_class
          Capybara.drivers[Capybara.current_driver].call({}).class
        end

        private def selenium?
          current_capybara_driver_class <= Capybara::Selenium::Driver
        end

        private def poltergeist?
          return false unless defined?(Capybara::Poltergeist::Driver)
          current_capybara_driver_class <= Capybara::Poltergeist::Driver
        end

        def screenshot_section(name)
          @screenshot_section = name.to_s
        end

        def screenshot_group(name)
          @screenshot_group = name.to_s
          @screenshot_counter = 0
          return unless Capybara::Screenshot.active? && name.present?
          FileUtils.rm_rf screenshot_dir
        end

        def screenshot(name, color_distance_limit: Capybara::Screenshot::Diff.color_distance_limit,
            area_size_limit: nil)
          return unless Capybara::Screenshot.active?
          return if window_size_is_wrong?
          if @screenshot_counter
            name = "#{format('%02i', @screenshot_counter)}_#{name}"
            @screenshot_counter += 1
          end
          name = full_name(name)
          file_name = "#{self.class.screenshot_area_abs}/#{name}.png"

          FileUtils.mkdir_p File.dirname(file_name)
          comparison = Capybara::Screenshot::Diff::ImageCompare.new(file_name,
              dimensions: Capybara::Screenshot.window_size, color_distance_limit: color_distance_limit,
              area_size_limit: area_size_limit)
          checkout_vcs(name, comparison)
          take_stable_screenshot(comparison)
          return unless comparison.old_file_exists?
          (@test_screenshots ||= []) << [caller[0], name, comparison]
        end

        private def window_size_is_wrong?
          selenium? && Capybara::Screenshot.window_size &&
            (!page.driver.chrome? || ON_WINDOWS) && # TODO(uwe): Allow for Chrome when it works
            page.driver.browser.manage.window.size !=
              Selenium::WebDriver::Dimension.new(*Capybara::Screenshot.window_size)
        end

        private def checkout_vcs(name, comparison)
          svn_file_name = "#{self.class.screenshot_area_abs}/.svn/text-base/#{name}.png.svn-base"
          if File.exist?(svn_file_name)
            committed_file_name = svn_file_name
            FileUtils.cp committed_file_name, comparison.old_file_name
          else
            svn_info = `svn info #{comparison.new_file_name} #{SILENCE_ERRORS}`
            if svn_info.present?
              wc_root = svn_info.slice(/(?<=Working Copy Root Path: ).*$/)
              checksum = svn_info.slice(/(?<=Checksum: ).*$/)
              if checksum
                committed_file_name = "#{wc_root}/.svn/pristine/#{checksum[0..1]}/#{checksum}.svn-base"
                FileUtils.cp committed_file_name, comparison.old_file_name
              end
            else
              restore_git_revision(name, comparison.old_file_name)
            end
          end
        end

        private def restore_git_revision(name, target_file_name)
          redirect_target = "#{target_file_name} #{SILENCE_ERRORS}"
          `git show HEAD~0:./#{self.class.screenshot_area}/#{name}.png > #{redirect_target}`
          FileUtils.rm_f(target_file_name) unless $CHILD_STATUS == 0
        end

        IMAGE_WAIT_SCRIPT = <<-EOF.strip_heredoc.freeze
          function pending_image() {
            var images = document.images;
            for (var i = 0; i < images.length; i++) {
              if (!images[i].complete) {
                  return images[i].src;
              }
            }
            return false;
          }()
        EOF

        def assert_images_loaded(timeout: Capybara.default_max_wait_time)
          return unless respond_to? :evaluate_script
          start = Time.now
          loop do
            pending_image = evaluate_script IMAGE_WAIT_SCRIPT
            break unless pending_image
            assert (Time.now - start) < timeout,
                "Images not loaded after #{timeout}s: #{pending_image.inspect}"
            sleep 0.1
          end
        end

        private def take_stable_screenshot(comparison)
          input = prepare_page_for_screenshot
          previous_file_name = comparison.old_file_name
          screeenshot_started_at = last_image_change_at = Time.now
          loop.with_index do |_x, i|
            take_right_size_screenshot(comparison)

            break unless Capybara::Screenshot.stability_time_limit
            if comparison.quick_equal?
              clean_stabilization_images(comparison.new_file_name)
              break
            end
            comparison.reset

            if previous_file_name
              stabilization_comparison =
                Capybara::Screenshot::Diff::ImageCompare.new(comparison.new_file_name, previous_file_name)
              if stabilization_comparison.quick_equal?
                if (Time.now - last_image_change_at) > Capybara::Screenshot.stability_time_limit
                  clean_stabilization_images(comparison.new_file_name)
                  break
                end
                next
              else
                last_image_change_at = Time.now
              end

              assert (Time.now - screeenshot_started_at) < Capybara.default_max_wait_time,
                  "Could not get stable screenshot within #{Capybara.default_max_wait_time}s\n" \
                      "#{stabilization_images(comparison.new_file_name).join("\n")}"
            end

            previous_file_name = "#{comparison.new_file_name.chomp('.png')}_x#{i}.png~"

            FileUtils.mv comparison.new_file_name, previous_file_name
          end
        ensure
          input.click if input
        end

        def take_right_size_screenshot(comparison)
          save_screenshot(comparison.new_file_name)

          # TODO(uwe): Remove when chromedriver takes right size screenshots
          reduce_retina_image_size(comparison.new_file_name)
          # ODOT
        end

        private def prepare_page_for_screenshot
          assert_images_loaded
          if Capybara::Screenshot.blur_active_element
            active_element = execute_script(<<-JS)
              ae = document.activeElement;
              if (ae.nodeName == "INPUT" || ae.nodeName == "TEXTAREA") {
                  ae.blur();
                  return ae;
              }
              return null;
            JS
            input = page.driver.send :unwrap_script_result, active_element
          end
          input
        end

        private def clean_stabilization_images(base_file)
          FileUtils.rm stabilization_images(base_file)
        end

        private def stabilization_images(base_file)
          Dir["#{base_file.chomp('.png')}_x*.png~"]
        end

        private def reduce_retina_image_size(file_name)
          return if !self.class.macos? || !selenium? || !Capybara::Screenshot.window_size
          saved_image = ChunkyPNG::Image.from_file(file_name)
          width = Capybara::Screenshot.window_size[0]
          return if saved_image.width < width * 2
          height = (width * saved_image.height) / saved_image.width
          resized_image = saved_image.resample_bilinear(width, height)
          resized_image.save(file_name)
        end

        def assert_image_not_changed(caller, name, comparison)
          return unless comparison.different?
          "Screenshot does not match for '#{name}' (area: #{comparison.size}px #{comparison.dimensions}" \
            ", max_color_distance: #{comparison.max_color_distance.ceil(1)})\n" \
            "#{comparison.new_file_name}\n#{comparison.annotated_old_file_name}\n" \
            "#{comparison.annotated_new_file_name}\n" \
            "at #{caller}"
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength

module ActionDispatch
  class IntegrationTest
    prepend Capybara::Screenshot::Diff::TestMethods

    setup do
      if Capybara::Screenshot.window_size
        if selenium?
          # TODO(uwe): Enable for Chrome and non-windows when it works)
          if !page.driver.chrome? || ON_WINDOWS
            page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
          end
        elsif poltergeist?
          page.driver.resize(*Capybara::Screenshot.window_size)
        end
      end
    end

    teardown do
      if Capybara::Screenshot::Diff.enabled && @test_screenshots
        test_screenshot_errors = @test_screenshots
          .map { |caller, name, compare| assert_image_not_changed(caller, name, compare) }.compact
        fail(test_screenshot_errors.join("\n\n")) if test_screenshot_errors.any?
      end
    end
  end
end
