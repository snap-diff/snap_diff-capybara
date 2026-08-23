# frozen_string_literal: true

# SnapDiff.silence_deprecations? -- the one switch that silences BOTH halves
# of the story -- lives in snap_diff/removal.rb, not here: the other half
# (the driver features 2.1 removes) is announced from core files that outlive
# this one, and they cannot depend on a file the same deletion removes.
require "snap_diff/removal"

module SnapDiff
  # @api private
  #
  # Internal until the v2 namespace transition; not a public contract.
  #
  # Warn-once-per-subject deprecation engine for the legacy-namespace
  # shims: snap_diff/legacy_shims routes every +const_missing+ hit on an
  # old +Capybara::Screenshot::Diff+ / +CapybaraScreenshotDiff+ constant
  # through {.warn}, so each deprecated name warns exactly once per
  # process (ADR-004's v2 namespace transition).
  module Deprecation
    # Everything under lib/ is "the gem"; the first caller frame outside
    # it is the user code that referenced the deprecated name (same
    # filtering idea as BacktraceFilter in error_with_filtered_backtrace).
    GEM_LIB_DIR = File.expand_path("..", __dir__) + File::SEPARATOR
    # Emission channel: Kernel#warn, not a direct +$stderr.puts+.
    #
    # Kernel#warn delegates to +Warning.warn+ (Ruby >= 2.4), so anything
    # that hooks +Warning.warn+ -- a test suite that raises on warnings, a
    # custom log formatter, Ruby's own -W flag -- sees these messages the
    # same way it sees every other Ruby warning. Writing straight to
    # +$stderr+ would bypass that hook entirely and be invisible to any
    # caller who has customized +Warning+ behavior.
    MUTEX = Mutex.new
    @seen = {}
    @notified = false
    @notice_suppressed = false

    # The ONE line a v1 user gets, whichever door they came through. Most of
    # the v1 surface cannot warn per use -- the config accessors are plain
    # delegators and the eager aliases never reach const_missing -- so
    # without this a 2.x app is completely silent right up to the bare
    # NameError it gets on 3.0. Deliberately generic and once per process:
    # an actionable signal, not per-call stderr noise.
    MIGRATION_NOTICE =
      "[snap_diff deprecation] This process uses the v1 `Capybara::Screenshot*` / " \
      "`CapybaraScreenshotDiff*` API. It still works in 2.x and is REMOVED in 3.0 -- " \
      "see docs/UPGRADING.md for the SnapDiff replacements. Silence with " \
      "`SnapDiff.silence_deprecations = true` or SNAP_DIFF_SILENCE_DEPRECATIONS=1. " \
      "(shown once per process)"

    class << self
      # Emit {MIGRATION_NOTICE}, exactly once per process. Called from every
      # v1 entry that can be hooked: the const_missing shims (via {.warn}),
      # the generated legacy config accessors, and `include
      # Capybara::Screenshot[::Diff]`.
      # @return [void]
      def notice
        return if @notified || @notice_suppressed || SnapDiff.silence_deprecations?

        first_time = MUTEX.synchronize { @notified ? false : (@notified = true) }
        Kernel.warn(MIGRATION_NOTICE) if first_time
      end

      # @api private
      #
      # Suppresses {MIGRATION_NOTICE} for the rest of the process, without
      # touching the per-constant warnings. For hosts that ARE the v1
      # surface rather than users of it -- this gem's own test suite, which
      # configures through `Capybara::Screenshot.*` by design and would
      # otherwise print the notice on every run. Deliberately survives
      # {reset!}, which exists to give a single test a clean slate.
      # @return [void]
      def suppress_migration_notice!
        MUTEX.synchronize { @notice_suppressed = true }
      end

      # Emit a deprecation warning for +subject+, exactly once per unique
      # +subject+ per process -- preceded, the first time round, by
      # {MIGRATION_NOTICE}.
      #
      # @param subject [String] the deprecated old-namespace name being
      #   referenced, e.g. "Capybara::Screenshot::Diff::ImageCompare"
      # @param replacement [String] the new-namespace name to use instead
      # @return [void]
      def warn(subject, replacement)
        return if SnapDiff.silence_deprecations?

        notice

        first_time = MUTEX.synchronize do
          @seen.key?(subject) ? false : (@seen[subject] = true)
        end
        return unless first_time

        Kernel.warn(message_for(subject, replacement, caller_locations(1)))
      end

      # @api private
      #
      # Clears the seen-set. For tests only -- lets each example assert
      # "warns once" from a clean slate instead of leaking state across
      # the suite.
      # @return [void]
      def reset!
        MUTEX.synchronize do
          @seen.clear
          @notified = false
        end
      end

      private

      def message_for(subject, replacement, locations)
        message = "[snap_diff deprecation] `#{subject}` is deprecated (constant); " \
          "use `#{replacement}` instead."
        origin = origin_for(locations)
        origin ? "#{message} (called from #{origin})" : message
      end

      # First frame outside the gem's lib dir, formatted "file:line";
      # nil when every frame is internal (or paths are unavailable).
      def origin_for(locations)
        (locations || []).each do |location|
          path = location.absolute_path || location.path
          next if path.nil? || path.start_with?(GEM_LIB_DIR)

          return "#{path}:#{location.lineno}"
        end
        nil
      end
    end
  end
end
