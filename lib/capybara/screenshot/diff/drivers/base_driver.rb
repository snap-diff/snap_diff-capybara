# frozen_string_literal: true

require "capybara/screenshot/diff/difference"
require "snap_diff/driver"

module Capybara
  module Screenshot
    module Diff
      # Compare two images and determine if they are equal, different, or within some comparison
      # range considering color values and difference area size.
      module Drivers
        class BaseDriver
          include SnapDiff::Driver
        end
      end
    end
  end
end
