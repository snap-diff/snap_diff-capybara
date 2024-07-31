# frozen_string_literal: true

require "capybara/screenshot/diff/vcs"
require "active_support/core_ext/module/attribute_accessors"

module CapybaraScreenshotDiff
  class SnapManager
    class Snap
      attr_reader :screenshot_full_name, :screenshot_format, :path, :base_path, :manager

      def initialize(screenshot_full_name, screenshot_format, manager: SnapManager.instance)
        @screenshot_full_name = screenshot_full_name
        @screenshot_format = screenshot_format
        @path = manager.abs_path_for(Pathname.new(@screenshot_full_name).sub_ext(".#{@screenshot_format}"))
        @base_path = @path.sub_ext(".base.#{@screenshot_format}")
        @manager = manager
      end

      def delete!
        path.delete if path.exist?
        base_path.delete if base_path.exist?
      end

      def checkout_base_screenshot
        @manager.checkout_file(path, base_path)
      end
    end

    attr_reader :root

    def initialize(root)
      @root = root
    end

    def snap_for(screenshot_full_name, screenshot_format = "png")
      Snap.new(screenshot_full_name, screenshot_format, manager: self)
    end

    def abs_path_for(path)
      @root / path
    end

    def checkout_file(path, as_path)
      create_output_directory_for(as_path) unless as_path.exist?
      Capybara::Screenshot::Diff::Vcs.checkout_vcs(root, path, as_path)
    end

    def create_output_directory_for(path)
      path.dirname.mkpath
    end

    def clean!
      FileUtils.rm_rf root
    end

    def self.clean!
      instance.clean!
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
      instance.screenshots
    end

    def self.snapshot(screenshot_full_name, screenshot_format = "png")
      instance.snap_for(screenshot_full_name, screenshot_format)
    end

    def self.cleanup_attempts_screenshots(base_file)
      instance.cleanup_attempts_screenshots(base_file)
    end

    def self.attempts_screenshot_paths(base_file)
      instance.attempts_screenshot_paths(base_file)
    end

    def self.gen_next_attempt_path(screenshot_path, iteration)
      instance.gen_next_attempt_path(screenshot_path, iteration)
    end

    def self.move_screenshot_to(new_screenshot_path, screenshot_path)
      instance.move_screenshot_to(new_screenshot_path, screenshot_path)
    end

    def self.root
      instance.root
    end

    def self.instance
      Capybara::Screenshot::Diff.manager.new(Capybara::Screenshot.screenshot_area_abs)
    end
  end
end
