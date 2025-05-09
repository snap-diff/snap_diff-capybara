# frozen_string_literal: true

module Capybara
  module Screenshot
    module Diff
      # Abstract base class for all screenshot‐capture strategies.
      # A concrete strategy receives the raw capture/comparison option hashes,
      # leaving them intact for now (we will introduce typed option objects in a
      # later phase). It must implement `#take_comparison_screenshot` accepting
      # a Snap.
      class CaptureStrategy
        def initialize(capture_options, comparison_options)
          @capture_options = capture_options
          @comparison_options = comparison_options
        end

        # @param snapshot [CapybaraScreenshotDiff::Snap]
        # @return [void]
        def take_comparison_screenshot(_snapshot)
          raise NotImplementedError, "subclass responsibility"
        end

        private

        attr_reader :capture_options, :comparison_options
      end
    end
  end
end
