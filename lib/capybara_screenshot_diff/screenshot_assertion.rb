# frozen_string_literal: true

require "snap_diff/screenshot_assertion"

module CapybaraScreenshotDiff
  ScreenshotAssertion = SnapDiff::ScreenshotAssertion
  AssertionRegistry = SnapDiff::AssertionRegistry
end

# The registry/reporters module-level machinery below is deliberately NOT
# moved in this PR. It's global per-thread state plumbing (the assertion
# registry, reporter list, verify/reset/finalize_reporters! lifecycle) in
# the same category as Config's old mattr_accessors -- an "ownership"
# change, not a mechanical move, and out of scope here (see the v2
# file-tree-move PR description). It stays attached to
# CapybaraScreenshotDiff, just updated to reference the two classes
# above at their new SnapDiff:: names.
module CapybaraScreenshotDiff
  class << self
    require "forwardable"
    extend Forwardable

    def registry
      Thread.current[:capybara_screenshot_diff_registry] ||= AssertionRegistry.new
    end

    def_delegator :registry, :add_assertion
    def_delegator :registry, :assertions
    def_delegator :registry, :assertions_present?
    def_delegator :registry, :failed_assertions
    def_delegator :registry, :record_new_screenshot
    def_delegator :registry, :new_screenshots
    def_delegator :registry, :new_screenshots_present?
    def reset
      notify_reporters(registry.assertions)
      registry.reset
    end

    def reporters
      @reporters ||= []
    end

    attr_reader :reporters_mutex

    def finalize_reporters!
      reporters_mutex.synchronize { reporters.dup }.each do |reporter|
        reporter.finalize
        if (msg = reporter.summary)
          $stdout.puts msg
        end
      rescue => e
        warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
      end
    end

    def_delegator :registry, :screenshot_namer
    def_delegator :registry, :verify

    # Message to skip the test with when a new screenshot has no baseline yet
    # and `pending_if_new` is enabled. Adapters call this after verifying
    # screenshots, and skip the test with the returned message when present.
    #
    # @return [String, nil] the pending message, or nil when there is nothing to report
    def pending_screenshots_message
      return unless ::Capybara::Screenshot::Diff.pending_if_new && new_screenshots_present?

      "No baseline for: #{new_screenshots.join(", ")}. Commit the captured screenshots to record them."
    end

    private

    def notify_reporters(assertions)
      return if assertions.nil? || assertions.empty?

      reporters_snapshot = reporters_mutex.synchronize { reporters.dup }
      return if reporters_snapshot.empty?

      reporters_snapshot.each do |reporter|
        reporter.record(assertions)
      rescue => e
        warn "[capybara-screenshot-diff] Reporter failed: #{e.message}"
      end
    end
  end

  @reporters_mutex = Mutex.new
end
