# frozen_string_literal: true

module SnapDiff
  # @api private
  #
  # Announces what 2.1 REMOVES, from the 2.0 line that still supports it:
  # the chunky_png driver, +shift_distance_limit+ (chunky-only, it dies with
  # it) and the driver abstraction (+SnapDiff::Driver+,
  # +SnapDiff::Drivers.loaded+ / +.available+, <tt>driver: :auto</tt>) --
  # libvips becomes the only backend. 2.0 is the transitional release: the
  # contract is published before it is enforced.
  #
  # Same shape and same silencing switches as {SnapDiff::Deprecation}, which
  # announces the other half (the v1 namespaces), but a file of its own: the
  # legacy shims and their deprecation channel are themselves part of what is
  # removed, while the call sites here -- utils, config, drivers -- are core
  # files that outlive them, so they cannot depend on a doomed file. That is
  # also why {SnapDiff.silence_deprecations} lives HERE rather than in
  # deprecation.rb: it is the one switch that silences both halves.
  #
  # Deliberately not a warn-per-call channel: one line per subject per
  # process is an actionable signal, N lines per comparison is noise people
  # learn to filter out.
  module Removal
    # Everything under lib/ is "the gem"; the first caller frame outside it
    # is the user code that touched the doomed API.
    GEM_LIB_DIR = File.expand_path("..", __dir__) + File::SEPARATOR

    # Appended to every message, so the individual messages can stay about
    # the thing being removed.
    SILENCE_HINT =
      "Silence with `SnapDiff.silence_deprecations = true` or " \
      "SNAP_DIFF_SILENCE_DEPRECATIONS=1. (shown once per process)"

    # The one message with two call sites -- the setting's writer (Config)
    # and the per-comparison option (Comparison) -- so it lives here rather
    # than in either of them. One subject, one warning, whichever fires.
    SHIFT_DISTANCE_LIMIT_REMOVED =
      "`shift_distance_limit` is REMOVED in 2.1: it is implemented only by the chunky_png " \
      "driver, which is removed with it. libvips has no shift-distance comparison -- drop the " \
      "option and tune `tolerance` / `color_distance_limit` instead. See docs/configuration.md."

    MUTEX = Mutex.new
    @seen = {}
    @suppressed = false

    class << self
      # Emit +message+ once per +subject+ per process, via Kernel#warn (so
      # anything hooking +Warning.warn+ sees it like any other Ruby warning).
      #
      # @param subject [Symbol] dedup key -- the doomed API, not the call site
      # @param message [String] what is removed, when, and what to do instead
      # @return [void]
      def warn_once(subject, message)
        return if @suppressed || SnapDiff.silence_deprecations?

        first_time = MUTEX.synchronize { @seen.key?(subject) ? false : (@seen[subject] = true) }
        return unless first_time

        Kernel.warn(with_origin("[snap_diff deprecation] #{message} #{SILENCE_HINT}", caller_locations(1)))
      end

      # @api private
      #
      # Silences these warnings for the rest of the process, without touching
      # the v1-namespace ones. For hosts that exercise the doomed APIs BY
      # DESIGN rather than depending on them -- this gem's own suite runs the
      # whole comparison matrix on chunky_png and sets shift_distance_limit,
      # and its test_helper raises on any deprecation output.
      # @return [void]
      def suppress!
        MUTEX.synchronize { @suppressed = true }
      end

      private

      def with_origin(message, locations)
        origin = origin_for(locations)
        origin ? "#{message} (called from #{origin})" : message
      end

      # First frame outside the gem's lib dir, formatted "file:line"; nil
      # when every frame is internal (or paths are unavailable).
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
