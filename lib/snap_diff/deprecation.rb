# frozen_string_literal: true

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

    class << self
      # Emit a deprecation warning for +subject+, exactly once per unique
      # +subject+ per process.
      #
      # @param subject [String] the deprecated old-namespace name being
      #   referenced, e.g. "Capybara::Screenshot::Diff::ImageCompare"
      # @param replacement [String] the new-namespace name to use instead
      # @return [void]
      def warn(subject, replacement)
        return if SnapDiff.silence_deprecations?

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
        MUTEX.synchronize { @seen.clear }
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

  class << self
    # @api private
    attr_accessor :silence_deprecations

    # @api private
    #
    # @return [Boolean] true if deprecation warnings should be suppressed,
    #   either via the {silence_deprecations} accessor or the
    #   SNAP_DIFF_SILENCE_DEPRECATIONS env var (truthy = "1"/"true").
    def silence_deprecations?
      !!silence_deprecations || truthy_env?(ENV["SNAP_DIFF_SILENCE_DEPRECATIONS"])
    end

    private

    def truthy_env?(value)
      %w[1 true].include?(value.to_s.downcase)
    end
  end
end
