# frozen_string_literal: true

require "fileutils"
require "pathname"

module CapybaraScreenshotDiff
  # Handles the naming, path generation, and organization of screenshots.
  # This class encapsulates logic related to screenshot sections, groups,
  # and counters, providing a centralized way to determine screenshot filenames
  # and directories.
  class ScreenshotNamer
    attr_reader :section, :group

    def initialize(screenshot_area = nil)
      @section = nil
      @group = nil
      @counter = nil
      @screenshot_area = screenshot_area
    end

    def screenshot_area
      @screenshot_area ||= Capybara::Screenshot.screenshot_area
    end

    # Sets the current section for screenshots.
    # @param name [String, nil] The name of the section.
    def section=(name)
      @section = name&.to_s
      reset_group_counter
    end

    # Sets the current group for screenshots and resets the counter.
    # @param name [String, nil] The name of the group.
    def group=(name)
      @group = name&.to_s
      reset_group_counter
    end

    # Builds the full, unique name for a screenshot, including any counter.
    # @param base_name [String] The base name for the screenshot.
    # @return [String] The full screenshot name.
    def full_name(base_name)
      name = base_name.to_s

      if @counter
        name = format("%02i_%s", @counter, name)
        @counter += 1
      end

      File.join(*directory_parts.push(name.to_s))
    end

    # Builds the full path for a screenshot file, including section and group directories.
    # @param base_name [String] The base name for the screenshot.
    # @return [String] The absolute path for the screenshot file.
    def full_name_with_path(base_name)
      File.join(screenshot_area, full_name(base_name))
    end

    # Returns the directory parts (section and group) for constructing paths.
    # @return [Array<String>] An array of directory names.
    def directory_parts
      parts = []
      parts << @section unless @section.nil? || @section.empty?
      parts << @group unless @group.nil? || @group.empty?
      parts
    end

    # Calculates the directory path for the current section and group.
    # @return [String] The full path to the directory.
    def current_group_directory
      File.join(*([screenshot_area] + directory_parts))
    end

    # Clears the directory for the current screenshot group.
    # This is typically used when starting a new group to remove old screenshots.
    def clear_current_group_directory
      dir_to_clear = current_group_directory
      FileUtils.rm_rf(dir_to_clear) if Dir.exist?(dir_to_clear)
    end

    private

    def reset_group_counter
      @counter = (@group.nil? || @group.empty?) ? nil : 0
    end
  end
end
