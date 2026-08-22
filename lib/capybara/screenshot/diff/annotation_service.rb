# frozen_string_literal: true

require "snap_diff/annotation_service"

module Capybara
  module Screenshot
    module Diff
      AnnotationService = SnapDiff::AnnotationService
    end
  end
end
