# frozen_string_literal: true

require "snap_diff/contributions"

# Optional AI triage. A backend is any object responding to
# #call(name:, base:, current:, meta:) -> Hash; register one by name or
# pass an instance. Builders run lazily, so optional gems load only when
# their backend is used. Advisory by default: pixel diff stays the verdict
# unless a reporter is configured with fail_on: (see AISimple).
#
# Results live in a process-wide store so ANY consumer can read them --
# the AISimple reporter writes, and reports pick them up through the
# SnapDiff::Contributions registry (no consumer names this module).
# Keyed by screenshot name; later writes win.
module SnapDiff
  module AI
    # The only verdicts a backend may return; anything else maps to
    # "unknown", which the fail-gate never suppresses.
    VERDICTS = %w[real_bug intentional flaky unknown].freeze

    @backends = {}
    @results = {}
    @mutex = Mutex.new

    class << self
      # Report contribution (SnapDiff::Contributions): whatever the store
      # holds for this screenshot, rendered one line plus the raw payload.
      def annotate(name)
        result = self[name]
        result && {source: "ai", text: format(result), data: result}
      end

      def register(name, &build)
        @mutex.synchronize { @backends[name.to_sym] = build }
      end

      def names
        @mutex.synchronize { @backends.keys }
      end

      # nil/:default -> :clip; a Symbol -> registered builder; anything
      # else must be a backend instance responding to #call.
      def resolve(input = nil)
        return build((input.nil? || input == :default) ? :clip : input) if input.nil? || input.is_a?(Symbol)

        unless input.respond_to?(:call)
          raise ArgumentError, "AI backend must respond to #call(name:, base:, current:, meta:), got #{input.inspect}"
        end
        input
      end

      def build(name)
        builder = @mutex.synchronize { @backends[name.to_sym] } or
          raise ArgumentError, "unknown AI backend #{name.inspect} (registered: #{names.map(&:inspect).join(", ")})"
        builder.call
      end

      # One-line rendering of a result, shared by the AISimple log and the
      # assertion failure message: "REAL_BUG (clip, similarity=0.73) -- CTA clipped".
      def format(result)
        line = "#{result[:verdict].upcase} (#{result[:backend]}"
        line += ", similarity=#{result[:similarity]}" if result[:similarity]
        line += ", confidence=#{result[:confidence]}" if result[:confidence]
        line += ")"
        line += " -- #{result[:summary]}" if result[:summary]
        line
      end

      # similarity -> verdict. The one place thresholds live.
      # Anything but a finite number is "unknown" -- NaN/Infinity would
      # otherwise classify as flaky and let the gate suppress a real diff.
      def verdict(similarity, flaky: 0.985, intentional: 0.90)
        return "unknown" unless similarity.is_a?(Numeric) && similarity.finite?

        if similarity >= flaky
          "flaky"
        elsif similarity >= intentional
          "intentional"
        else
          "real_bug"
        end
      end

      # --- shared result store ------------------------------------------

      def record_result(result)
        @mutex.synchronize { @results[result[:name]] = result }
      end

      def [](name)
        @mutex.synchronize { @results[name] }
      end

      def results
        @mutex.synchronize { @results.values }
      end

      # Test isolation hook, same role as Reporting.reset_run_totals!.
      def clear_results!
        @mutex.synchronize { @results.clear }
      end

      # Fork-parallel: plain hashes round-trip via JSON fragments.
      def dump_state
        {"results" => results}
      end

      def merge_state!(state)
        Array(state.is_a?(Hash) && state["results"]).each { |r| record_result(r.transform_keys(&:to_sym)) }
      end
    end
  end
end

require "snap_diff/ai/backends/clip"

# Minitest-style self-registration: loading this file opts into
# annotating reports. Core (HTML reporter, assertion message) only ever
# talks to SnapDiff::Contributions and never references this module.
SnapDiff::Contributions.register(SnapDiff::AI)
