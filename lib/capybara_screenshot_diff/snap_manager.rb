# frozen_string_literal: true

require "capybara/screenshot/diff/vcs"
require "active_support/core_ext/module/attribute_accessors"

require "capybara_screenshot_diff/snap"

module CapybaraScreenshotDiff
  class SnapManager

    attr_reader :root

    def initialize(root)
      @root = Pathname.new(root)
    end

    def snapshot(screenshot_full_name, screenshot_format = "png")
      Snap.new(screenshot_full_name, screenshot_format, manager: self)
    end

    def self.snapshot(screenshot_full_name, screenshot_format = "png")
      instance.snapshot(screenshot_full_name, screenshot_format)
    end

    def abs_path_for(relative_path)
      @root / relative_path
    end

    def checkout_file(path, as_path)
      create_output_directory_for(as_path) unless as_path.exist?
      Capybara::Screenshot::Diff::Vcs.checkout_vcs(root, path, as_path)
    end

    def provision_snap_with(snap, path, version: :actual)
      managed_path = snap.path_for(version)
      create_output_directory_for(managed_path) unless managed_path.exist?
      FileUtils.cp(path, managed_path)
    end

    def create_output_directory_for(path = nil)
      path ? path.dirname.mkpath : root.mkpath
    end

    # TODO: rename to delete!
    def cleanup!
      FileUtils.rm_rf root, secure: true
    end

    def cleanup_attempts!(snapshot)
      FileUtils.rm_rf snapshot.find_attempts_paths, secure: true
    end

    def move(new_screenshot_path, screenshot_path)
      FileUtils.mv(new_screenshot_path, screenshot_path, force: true)
    end

    def screenshots
      root.children.map { |f| f.basename.to_s }
    end

    def self.screenshots
      instance.screenshots
    end

    def self.root
      instance.root
    end

    def self.instance
      Capybara::Screenshot::Diff.manager.new(Capybara::Screenshot.screenshot_area_abs)
    end
  end
end
