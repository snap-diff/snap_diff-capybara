# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      module Utils
        def self.detect_available_drivers
          result = []
          begin
            result << :vips if defined?(Vips) || require("vips")
          rescue LoadError
            # vips not present
          end
          begin
            result << :chunky_png if defined?(ChunkyPNG) || require("chunky_png")
          rescue LoadError
            # chunky_png not present
          end
          result
        end
      end
    end
  end
end
