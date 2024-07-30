# frozen_string_literal: true

require "capybara/screenshot/diff/vcs"
require "active_support/core_ext/module/attribute_accessors"

module CapybaraScreenshotDiff
  class SnapManager

    class Snap
      attr_reader :screenshot_full_name, :screenshot_format, :screenshot_path, :base_screenshot_path

      def initialize(screenshot_full_name, screenshot_format)
        @screenshot_full_name = screenshot_full_name
        @screenshot_format = screenshot_format
        @screenshot_path = SnapManager.image_path_for(screenshot_full_name, screenshot_format)
        @base_screenshot_path = SnapManager.base_image_path_from(@screenshot_path)
      end

      def delete!
        @screenshot_path.delete if @screenshot_path.exist?
        @base_screenshot_path.delete if @base_screenshot_path.exist?
      end
    end

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def snap_for(screenshot_full_name, screenshot_format)
      Snap.new(screenshot_full_name, screenshot_format)
    end

    def image_path_for(screenshot_full_name, screenshot_format)
      @root / Pathname.new(screenshot_full_name).sub_ext(".#{screenshot_format}")
    end

    def checkout_base_screenshot(screenshot_path)
      create_output_directory_for(screenshot_path) unless screenshot_path.exist?

      Capybara::Screenshot::Diff::Vcs.checkout_vcs(screenshot_path, base_image_path_from(screenshot_path), root)
    end

    def create_output_directory_for(screenshot_path)
      screenshot_path.dirname.mkpath
    end

    def delete_output_directory_for

    end

    def base_image_path_from(screenshot_path)
      screenshot_path.sub_ext(".base#{screenshot_path.extname}")
    end

    def cleanup_attempts_screenshots(base_file)
      FileUtils.rm_rf attempts_screenshot_paths(base_file)
    end

    def attempts_screenshot_paths(base_file)
      extname = Pathname.new(base_file).extname
      Dir["#{base_file.to_s.chomp(extname)}.attempt_*#{extname}"].sort
    end

    def gen_next_attempt_path(screenshot_path, iteration)
      screenshot_path.sub_ext(format(".attempt_%02i#{screenshot_path.extname}", iteration))
    end

    def move_screenshot_to(new_screenshot_path, screenshot_path)
      FileUtils.mv(new_screenshot_path, screenshot_path, force: true)
    end

    def screenshots
      root.children.map { |f| f.basename.to_s }
    end

    def self.screenshots
      manager.screenshots
    end

    def self.snapshot(screenshot_full_name, screenshot_format = "png")
      manager.snap_for(screenshot_full_name, screenshot_format)
    end

    def self.image_path_for(screenshot_full_name, screenshot_format)
      manager.image_path_for(screenshot_full_name, screenshot_format)
    end

    def self.checkout_base_screenshot(screenshot_path)
      manager.checkout_base_screenshot(screenshot_path)
    end

    def self.create_output_directory_for(screenshot_path)
      manager.create_output_directory_for(screenshot_path)
    end

    def self.base_image_path_from(screenshot_path)
      manager.base_image_path_from(screenshot_path)
    end

    def self.cleanup_attempts_screenshots(base_file)
      manager.cleanup_attempts_screenshots(base_file)
    end

    def self.attempts_screenshot_paths(base_file)
      manager.attempts_screenshot_paths(base_file)
    end

    def self.gen_next_attempt_path(screenshot_path, iteration)
      manager.gen_next_attempt_path(screenshot_path, iteration)
    end

    def self.move_screenshot_to(new_screenshot_path, screenshot_path)
      manager.move_screenshot_to(new_screenshot_path, screenshot_path)
    end

    def self.manager
      Capybara::Screenshot::Diff.manager.new(Capybara::Screenshot.screenshot_area_abs)
    end
  end
end
