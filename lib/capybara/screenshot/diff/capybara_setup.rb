require 'capybara'
require 'capybara/screenshot/diff/image_compare'

# Add the `screenshot`method to ActionDispatch::IntegrationTest
class ActionDispatch::IntegrationTest
  ON_WINDOWS = RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
  SILENCE_ERRORS = ON_WINDOWS ? '2>nul' : '2>/dev/null'

  def self.screenshot_dir
    parts = ['doc/screenshots']
    parts << Capybara.default_driver.to_s if Capybara::Screenshot.add_driver_path
    parts << RbConfig::CONFIG['host_os'] if Capybara::Screenshot.add_os_path
    File.join parts
  end

  def self.screenshot_dir_abs
    "#{Rails.root}/#{screenshot_dir}".freeze
  end

  setup do
    if Capybara::Screenshot.window_size
      if Capybara.default_driver == :selenium
        page.driver.browser.manage.window.resize_to(*Capybara::Screenshot.window_size)
      else
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

  def screenshot_group(name)
    @screenshot_group = name
    @screenshot_counter = 0
    FileUtils.rm_rf "#{self.class.screenshot_dir_abs}/#{name}" if name.present?
  end

  def screenshot(name)
    return unless Capybara::Screenshot.enabled || (Capybara::Screenshot.enabled.nil? && Capybara::Screenshot::Diff.enabled)
    if Capybara.default_driver == :selenium && Capybara::Screenshot.window_size
      return unless page.driver.browser.manage.window
          .size == Selenium::WebDriver::Dimension.new(*Capybara::Screenshot.window_size)
    end
    if @screenshot_counter
      name = "#{'%02i' % @screenshot_counter}_#{name}"
      @screenshot_counter += 1
    end
    name = "#{@screenshot_group}/#{name}" if @screenshot_group.present?
    file_name = "#{self.class.screenshot_dir_abs}/#{name}.png"
    svn_file_name = "#{self.class.screenshot_dir_abs}/.svn/text-base/#{name}.png.svn-base"
    org_name = "#{self.class.screenshot_dir_abs}/#{name}_0.png~"
    new_name = "#{self.class.screenshot_dir_abs}/#{name}_1.png~"
    FileUtils.mkdir_p File.dirname(org_name)
    unless File.exist?(svn_file_name)
      svn_info = `svn info #{file_name} #{SILENCE_ERRORS}`
      if svn_info.blank?
        FileUtils.mkdir_p File.dirname(org_name)
        puts `git show HEAD~0:#{self.class.screenshot_dir_abs}/#{name}.png > #{org_name} #{SILENCE_ERRORS}`
        if File.size(org_name) == 0
          FileUtils.rm_f org_name
        else
          svn_file_name = org_name
        end
      else
        wc_root = svn_info.slice /(?<=Working Copy Root Path: ).*$/
        checksum = svn_info.slice /(?<=Checksum: ).*$/
        if checksum
          svn_file_name = "#{wc_root}/.svn/pristine/#{checksum[0..1]}/#{checksum}.svn-base"
        end
      end
    end
    old_file_size = nil
    loop do
      page.save_screenshot(file_name)
      break if old_file_size == File.size(file_name)
      old_file_size = File.size(file_name)
      sleep 0.5
    end
    return unless File.exist?(svn_file_name)
    (@test_screenshots ||= []) << [caller[0], file_name, name, new_name, org_name]
  end

  def assert_image_not_changed(caller, file_name, name, new_name, org_name)
    if ImageCompare.compare(file_name, org_name, Capybara::Screenshot.window_size)
      (@test_screenshot_errors ||= []) <<
          "Screenshot does not match for #{name.inspect}\n#{file_name}\n#{org_name}\n#{new_name}\nat #{caller}"
    end
  end
end
