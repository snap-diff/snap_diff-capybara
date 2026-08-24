# frozen_string_literal: true

module SnapDiff
  # Process-global reporter lifecycle: registration, per-test notification,
  # end-of-suite finalization. One list of reporters for the whole process,
  # guarded by one mutex.
  #
  # Deliberately separate from the per-test session lifecycle
  # (SnapDiff.session): reporters outlive any single test, the session does
  # not. CapybaraScreenshotDiff keeps its public
  # reporters/reporters_mutex/finalize_reporters! methods as thin shims
  # over this module.
  module Reporting
    @reporters = []
    @mutex = Mutex.new
    @missing_baselines = Set.new

    class << self
      attr_reader :reporters, :mutex

      # Remembers a screenshot that had no COMMITTED baseline and was
      # therefore never compared.
      #
      # @return [Boolean] true the first time this name is seen -- the
      #   "warn once per screenshot" gate for ScreenshotMatcher, and the
      #   tally behind {finalize!}'s summary line. Kept here rather than in
      #   the matcher because the end-of-run summary is this module's job.
      def record_missing_baseline(name)
        @mutex.synchronize { !!@missing_baselines.add?(name) }
      end

      # How many screenshots were captured but never compared. The "new"
      # count on the end-of-run summary line, and live state: it is the
      # number of screenshots that actually went down the no-baseline path
      # this run, not a number derived from what the run should have done.
      def missing_baselines_count
        @mutex.synchronize { @missing_baselines.size }
      end

      # @api private
      # Per-test isolation for this gem's own suite.
      def reset_missing_baselines!
        @mutex.synchronize { @missing_baselines.clear }
      end

      # Registers a reporter for the rest of the process. The canonical way
      # in: the append happens under the mutex, so concurrent registrations
      # cannot lose one (issue #217 item 2). `reporters` stays public and
      # mutable for compatibility -- appending to it directly still works,
      # it just skips the lock.
      def register(reporter)
        @mutex.synchronize { @reporters << reporter }
        reporter
      end

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
          warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
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

        if (msg = missing_baselines_summary)
          $stdout.puts msg
        end
      end

      # The reporters' summary line carries the COUNT of screenshots that
      # were captured without a committed baseline ("N new (not
      # verified)"); this line names them, so the next thing the reader
      # does is `git add` the right files.
      #
      # @return [String, nil] nil when every screenshot had a baseline
      def missing_baselines_summary
        names = @mutex.synchronize { @missing_baselines.to_a }
        return if names.empty?

        label = (names.size == 1) ? "1 screenshot" : "#{names.size} screenshots"
        "[snap_diff] #{label} had no committed baseline and #{(names.size == 1) ? "was" : "were"} NOT compared: " \
          "#{names.join(", ")}. Commit the captured file(s) to enable comparison."
      end
    end
  end
end
