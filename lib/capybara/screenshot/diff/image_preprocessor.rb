# frozen_string_literal: true

require "snap_diff/image_preprocessor"

module Capybara
  module Screenshot
    module Diff
      ImagePreprocessor = SnapDiff::ImagePreprocessor
    end
  end
end
