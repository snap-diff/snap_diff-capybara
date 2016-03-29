require 'capybara'
require 'capybara/screenshot/diff/image_compare'

# Add the `screenshot`method to ActionDispatch::IntegrationTest
class ActionDispatch::IntegrationTest
  WINDOW_SIZE = [1280, 1024].freeze

  def self.screenshot_dir
    "doc/screenshots/#{Capybara.default_driver}".freeze
  end

  def self.screenshot_dir_abs
    "#{Rails.root}/#{screenshot_dir}".freeze
  end

  setup do
    if Capybara.default_driver == :selenium
      Capybara.current_session.driver.browser.manage.window
          .resize_to(*WINDOW_SIZE)
      Capybara.current_session.driver.browser.manage.timeouts.page_load = 300
    else
      Capybara.current_session.driver.resize(*WINDOW_SIZE)
    end
  end

  teardown do
    fail(@test_screenshot_errors.join("\n")) if @test_screenshot_errors
  end

  def screenshot(name)
    if Capybara.default_driver == :selenium
      return unless Capybara.current_session.driver.browser.manage.window
            .size == Selenium::WebDriver::Dimension.new(*WINDOW_SIZE)
    end
    file_name = "#{self.class.screenshot_dir_abs}/#{name}.png"
    svn_file_name = "#{self.class.screenshot_dir_abs}/.svn/text-base/#{name}.png.svn-base"
    org_name = "#{self.class.screenshot_dir_abs}/#{name}_0.png~"
    new_name = "#{self.class.screenshot_dir_abs}/#{name}_1.png~"
    FileUtils.mkdir_p File.dirname(org_name)
    unless File.exist?(svn_file_name)
      svn_info = `svn info #{file_name}`
      if svn_info.blank?
        # http://www.akikoskinen.info/image-diffs-with-git/
        puts `git show HEAD~0:#{self.class.screenshot_dir}/#{name}.png > #{org_name}`
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
    if Capybara.default_driver == :selenium
      comparison = Capybara::Screenshot::Diff::ImageCompare.compare(file_name, svn_file_name)
    else
      comparison = Capybara::Screenshot::Diff::ImageCompare.compare(file_name, svn_file_name, WINDOW_SIZE)
    end
    if comparison
      (@test_screenshot_errors ||= []) <<
        "Screenshot does not match for #{name.inspect}\n#{file_name}\n#{org_name}\n#{new_name}\n#{caller[0]}"
    end
  end
end
