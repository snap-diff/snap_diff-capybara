# frozen_string_literal: true

require "capybara/screenshot/diff/vcs"
require "active_support/core_ext/module/attribute_accessors"

module CapybaraScreenshotDiff
  class SnapManager
    class Snap
      attr_reader :full_name, :format, :path, :base_path, :manager, :prev_attempt_path, :attempts_count

      def initialize(full_name, format, manager: SnapManager.instance)
        @full_name = full_name
        @format = format
        @path = manager.abs_path_for(Pathname.new(@full_name).sub_ext(".#{@format}"))
        @base_path = @path.sub_ext(".base.#{@format}")
        @manager = manager
        @attempts_count = 0
      end

      def delete!
        path.delete if path.exist?
        base_path.delete if base_path.exist?
        cleanup_attempts
      end

      def checkout_base_screenshot
        @manager.checkout_file(path, base_path)
      end

      def path_for(version = :actual)
        case version
        when :base
          base_path
        else
          path
        end
      end

      def attach_attempt(a_path)
        @manager.move_screenshot_to(a_path, attempt_path)
        @attempts_count += 1
      end

      def attach(a_path, version: :actual)
        @manager.move_screenshot_to(a_path, path_for(version))
      end

      def attempt_path
        @_attempt_path ||= path.sub_ext(sprintf(".attempt_%02i.#{format}", @attempts_count))
      end

      def next_attempt_path!
        @prev_attempt_path = @_attempt_path
        @_attempt_path = nil

        attempt_path
      ensure
        @attempts_count += 1
      end

      def commit_last_attempt
        @manager.move_screenshot_to(attempt_path, path)
      end

      def cleanup_attempts
        @manager.cleanup_attempts_screenshots(self)
        @attempts_count = 0
      end

      def find_attempts_paths
        Dir[@manager.abs_path_for "**/#{full_name}.attempt_*.#{format}"]
      end
    end

    attr_reader :root

    def initialize(root)
      @root = Pathname.new(root)
    end

    def snap_for(screenshot_full_name, screenshot_format = "png")
      Snap.new(screenshot_full_name, screenshot_format, manager: self)
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

    def self.provision_snap_with(snap, path, version: :actual)
      instance.provision_snap_with(snap, path, version: version)
    end

    def create_output_directory_for(path = nil)
      path ? path.dirname.mkpath : root.mkpath
    end

    # TODO: rename to delete!
    def clean!
      FileUtils.rm_rf root
    end

    def self.clean!
      instance.clean!
    end

    def cleanup_attempts_screenshots(snapshot)
      FileUtils.rm_rf snapshot.find_attempts_paths
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
