# frozen_string_literal: true

module SnapDiff
  # @api private
  #
  # Internal until the v2 namespace transition; not a public contract.
  #
  # Warn-once-per-subject deprecation helper. Dormant: nothing in the
  # current codebase calls this yet -- it exists so the gated v2 shim layer
  # (ADR-004's +const_missing+-based legacy constant shim and the
  # mattr_accessor-to-Config method shims) has pre-tested warning
  # machinery to call into once it lands.
  module Deprecation
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
      # @param category [Symbol] what kind of thing moved, for the human
      #   reading the message (e.g. :constant, :config)
      # @return [void]
      def warn(subject, replacement, category:)
        return if SnapDiff.silence_deprecations?

        first_time = MUTEX.synchronize do
          @seen.key?(subject) ? false : (@seen[subject] = true)
        end
        return unless first_time

        Kernel.warn(message_for(subject, replacement, category))
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

      def message_for(subject, replacement, category)
        "[snap_diff deprecation] `#{subject}` is deprecated (#{category}); " \
          "use `#{replacement}` instead."
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
