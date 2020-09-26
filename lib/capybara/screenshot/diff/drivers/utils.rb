# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      module Utils
        def self.detect_available_drivers
          result = []
          result << :vips if defined?(Vips) || require('vips')
          result << :chunky_png if defined?(ChunkyPNG) || require('chunky_png')
          result
        end
      end
    end
  end
end
