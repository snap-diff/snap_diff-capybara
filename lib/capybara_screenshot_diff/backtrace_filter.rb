# frozen_string_literal: true

module CapybaraScreenshotDiff
  class BacktraceFilter
    LIB_DIRECTORY = File.expand_path(File.join(File.dirname(__FILE__), "..")) + File::SEPARATOR

    def initialize(lib_directory = LIB_DIRECTORY)
      @lib_directory = lib_directory
    end

    # Filters out any backtrace lines originating from the library directory or from gems such as ActiveSupport, Minitest, and Railties
    # @param backtrace [Array<String>]
    # @return [Array<String>]
    def filtered(backtrace)
      backtrace
        .reject { |location| File.expand_path(location).start_with?(@lib_directory) }
        .reject { |l| l =~ /gems\/(activesupport|minitest|railties)/ }
    end
  end
end
