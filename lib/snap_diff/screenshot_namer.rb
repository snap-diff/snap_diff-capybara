# frozen_string_literal: true

require "fileutils"
require "pathname"

module SnapDiff
  # Handles the naming, path generation, and organization of screenshots.
  # This class encapsulates logic related to screenshot sections, groups,
  # and counters, providing a centralized way to determine screenshot filenames
  # and directories.
  class ScreenshotNamer
    attr_reader :section, :group

    def initialize
      @section = nil
      @group = nil
      @counter = nil
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

    # Returns the directory parts (section and group) for constructing paths.
    # @return [Array<String>] An array of directory names.
    def directory_parts
      parts = []
      parts << @section unless @section.nil? || @section.empty?
      parts << @group unless @group.nil? || @group.empty?
      parts
    end

    private

    def reset_group_counter
      @counter = (@group.nil? || @group.empty?) ? nil : 0
    end
  end
end
