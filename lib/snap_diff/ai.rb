# frozen_string_literal: true

# Optional AI triage. A backend is any object responding to
# #call(name:, base:, current:, meta:) -> Hash; register one by name or
# pass an instance. Builders run lazily, so optional gems load only when
# their backend is used. Advisory only: pixel diff stays the verdict.
#
# Results live in a process-wide store so ANY consumer can read them --
# the AiSimple reporter writes, the HTML reporter annotates from it, CI
# scripts read ai_report.json. Keyed by screenshot name; later writes win.
module SnapDiff
  module Ai
    @backends = {}
    @results = {}
    @mutex = Mutex.new

    class << self
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

      # similarity -> verdict. The one place thresholds live.
      def verdict(similarity, flaky: 0.985, intentional: 0.90)
        return "unknown" if similarity.nil?

        (similarity >= flaky) ? "flaky" : (similarity >= intentional) ? "intentional" : "real_bug"
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
