require 'capybara'
require 'capybara/screenshot/diff/image_compare'
require 'action_controller'
require 'action_dispatch'

# TODO(uwe): Move this code to module Capybara::Screenshot::Diff::TestMethods,
#            and use Module#prepend/include to insert.
# Add the `screenshot` method to ActionDispatch::IntegrationTest
# rubocop:disable Metrics/ClassLength
module ActionDispatch
  class IntegrationTest
    ON_WINDOWS = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    SILENCE_ERRORS = ON_WINDOWS ? '2>nul' : '2>/dev/null'

    def self.os_name
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

    def self.screenshot_root
      Capybara::Screenshot.screenshot_root ||
        (defined?(Rails.root) && Rails.root) || File.expand_path('.')
    end

    def self.screenshot_area
      parts = ['doc/screenshots']
      parts << Capybara.default_driver.to_s if Capybara::Screenshot.add_driver_path
      parts << os_name if Capybara::Screenshot.add_os_path
      File.join parts
    end

    def self.screenshot_area_abs
      "#{screenshot_root}/#{screenshot_area}".freeze
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

    setup do
      if Capybara::Screenshot.window_size
        if Capybara.default_driver == :selenium
          page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
        elsif Capybara.default_driver == :poltergeist
          page.driver.resize(*Capybara::Screenshot.window_size)
        end
      end
    end

    teardown do
      if Capybara::Screenshot::Diff.enabled && @test_screenshots
        @test_screenshots.each { |args| assert_image_not_changed(*args) }
      end
      fail(@test_screenshot_errors.join("\n\n")) if @test_screenshot_errors
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

    def screenshot(name)
      return unless Capybara::Screenshot.active?
      if Capybara.default_driver == :selenium && Capybara::Screenshot.window_size
        return unless page.driver.browser.manage.window
              .size == Selenium::WebDriver::Dimension.new(*Capybara::Screenshot.window_size)
      end
      if @screenshot_counter
        name = "#{'%02i' % @screenshot_counter}_#{name}"
        @screenshot_counter += 1
      end
      name = full_name(name)
      file_name = "#{self.class.screenshot_area_abs}/#{name}.png"
      org_name = "#{self.class.screenshot_area_abs}/#{name}_0.png~"
      new_name = "#{self.class.screenshot_area_abs}/#{name}_1.png~"

      FileUtils.mkdir_p File.dirname(file_name)
      committed_file_name = check_vcs(name, file_name, org_name)
      take_stable_screenshot(file_name)
      return unless committed_file_name && File.exist?(committed_file_name)
      (@test_screenshots ||= []) << [caller[0], name, file_name, committed_file_name, new_name, org_name]
    end

    def check_vcs(name, file_name, org_name)
      svn_file_name = "#{self.class.screenshot_area_abs}/.svn/text-base/#{name}.png.svn-base"
      if File.exist?(svn_file_name)
        committed_file_name = svn_file_name
      else
        svn_info = `svn info #{file_name} #{SILENCE_ERRORS}`
        if svn_info.present?
          wc_root = svn_info.slice(/(?<=Working Copy Root Path: ).*$/)
          checksum = svn_info.slice(/(?<=Checksum: ).*$/)
          if checksum
            committed_file_name = "#{wc_root}/.svn/pristine/#{checksum[0..1]}/#{checksum}.svn-base"
          end
        else
          committed_file_name = org_name
          redirect_target = "#{committed_file_name} #{SILENCE_ERRORS}"
          `git show HEAD~0:#{self.class.screenshot_area}/#{name}.png > #{redirect_target}`
          if File.size(committed_file_name) == 0
            FileUtils.rm_f committed_file_name
          end
        end
      end
      committed_file_name
    end

    IMAGE_WAIT_SCRIPT = <<EOF.freeze
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
            "Image not loaded after #{timeout}s: #{pending_image.inspect}"
        sleep 0.1
      end
    end

    def take_stable_screenshot(file_name)
      assert_images_loaded
      old_file_size = nil
      loop do
        save_screenshot(file_name)
        break unless Capybara::Screenshot.stability_time_limit
        new_file_size = File.size(file_name)
        break if new_file_size == old_file_size
        old_file_size = new_file_size
        sleep Capybara::Screenshot.stability_time_limit
      end
    end

    def assert_image_not_changed(caller, name, file_name, committed_file_name, new_name, org_name)
      if Capybara::Screenshot::Diff::ImageCompare.compare(committed_file_name, file_name,
          Capybara::Screenshot.window_size)
        (@test_screenshot_errors ||= []) <<
          "Screenshot does not match for '#{name}'\n#{file_name}\n#{org_name}\n#{new_name}\nat #{caller}"
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
