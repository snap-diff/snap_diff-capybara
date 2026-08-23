# frozen_string_literal: true

require "fileutils"

require_relative "vcs"

require_relative "snap"

module SnapDiff
  class SnapManager
    attr_reader :root

    def initialize(root)
      @root = Pathname.new(root)
      @snapshots = Set.new
    end

    def snapshot(screenshot_full_name, screenshot_format = "png")
      Snap.new(screenshot_full_name, screenshot_format, manager: self).tap do |snapshot|
        @snapshots << snapshot
      end
    end

    def self.snapshot(screenshot_full_name, screenshot_format = "png")
      instance.snapshot(screenshot_full_name, screenshot_format)
    end

    # Pure path lookup: builds the Snap (path bundle) for a name WITHOUT
    # registering it for cleanup. Use this when you only need to know where
    # a screenshot lives; use #snapshot when taking one that cleanup! owns.
    def path_for(screenshot_full_name, screenshot_format = "png")
      Snap.new(screenshot_full_name, screenshot_format, manager: self)
    end

    def self.path_for(screenshot_full_name, screenshot_format = "png")
      instance.path_for(screenshot_full_name, screenshot_format)
    end

    def abs_path_for(relative_path)
      @root / relative_path
    end

    def checkout_file(path, as_path)
      create_output_directory_for(as_path) unless as_path.exist?
      SnapDiff::Vcs.checkout_vcs(root, path, as_path)
    end

    def provision_snap_with(snap, path, version: :actual)
      managed_path = snap.path_for(version)
      create_output_directory_for(managed_path) unless managed_path.exist?
      FileUtils.cp(path, managed_path)
    end

    def create_output_directory_for(path = nil)
      path ? path.dirname.mkpath : root.mkpath
    end

    def cleanup!
      snapshots.each do |snapshot|
        cleanup_attempts!(snapshot)
        snapshot.delete!
      end
      # With the manager memoized per thread the set would otherwise grow for
      # the whole run, and a later cleanup! could delete a path an earlier
      # test tracked but the current test re-provisioned.
      snapshots.clear
    end

    def self.cleanup!
      instance.cleanup!
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

    attr_reader :snapshots

    def self.screenshots
      instance.screenshots
    end

    def self.root
      instance.root
    end

    # Thread-local memoized manager (D7 fix): snapshots tracked via the
    # class-method path and class-method cleanup! now share one instance, so
    # cleanup! actually deletes what was tracked. Rebuilt when the configured
    # manager class or screenshot root changes (tests re-root per example).
    #
    # Thread.current[] is fiber-local — same construct as
    # SnapDiff.session; both split per fiber and must migrate
    # together if async support ever lands.
    #
    # Scope of the fix: default-root unit tests and before_setup re-rooters
    # get working cleanup. System tests do NOT — system_test_case.rb re-roots
    # in `setup do`, and LIFO teardown restores the root BEFORE test_helper's
    # cleanup! runs, so the root-mismatch check below rebuilds an empty
    # manager there. That miss is protective: firing cleanup on the restored
    # instance would delete committed baselines under
    # test/fixtures/app/doc/screenshots/ that VCS rollback just restored.
    # Do not reorder those teardowns without revisiting this.
    def self.instance
      manager_class = Capybara::Screenshot::Diff.manager
      root = Pathname.new(Capybara::Screenshot.screenshot_area_abs)

      current = Thread.current[:snap_diff_manager]
      unless current&.instance_of?(manager_class) && current.root == root
        current = Thread.current[:snap_diff_manager] = manager_class.new(root)
      end
      current
    end
  end
end
