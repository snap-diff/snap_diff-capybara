# frozen_string_literal: true

module SnapDiff
  # Process-global reporter lifecycle: registration, per-test notification,
  # end-of-suite finalization. One list of reporters for the whole process,
  # guarded by one mutex.
  #
  # Deliberately separate from the per-test session lifecycle (the
  # thread-local AssertionRegistry reached through
  # CapybaraScreenshotDiff.registry): reporters outlive any single test,
  # the registry does not. CapybaraScreenshotDiff keeps its public
  # reporters/reporters_mutex/finalize_reporters! methods as thin shims
  # over this module.
  module Reporting
    @reporters = []
    @mutex = Mutex.new

    class << self
      attr_reader :reporters, :mutex

      # Delivers a finished test's assertions to every registered reporter.
      # Iterates over a snapshot so a reporter mutating the list mid-notify
      # cannot affect the current round. A raising reporter is warned about
      # and skipped; the rest are still notified.
      def notify(assertions)
        return if assertions.nil? || assertions.empty?

        reporters_snapshot = @mutex.synchronize { @reporters.dup }
        return if reporters_snapshot.empty?

        reporters_snapshot.each do |reporter|
          reporter.record(assertions)
        rescue => e
          warn "[capybara-screenshot-diff] Reporter failed: #{e.message}"
        end
      end

      # End-of-suite hook: finalizes each reporter and prints its summary.
      # A raising reporter is warned about and skipped; the rest are still
      # finalized.
      def finalize!
        @mutex.synchronize { @reporters.dup }.each do |reporter|
          reporter.finalize
          if (msg = reporter.summary)
            $stdout.puts msg
          end
        rescue => e
          warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
        end
      end
    end
  end
end
