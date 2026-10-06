# frozen_string_literal: true

require "snap_diff/ai"

module SnapDiff
  module Reporters
    # Advisory AI triage: classifies every FAILED comparison as
    # flaky/intentional/real_bug and logs one line per diff. By default
    # never changes pass/fail; with fail_on: the verdict gates it instead.
    #
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new)           # offline CLIP
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: :jev))
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: my_backend))
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(fail_on: %w[real_bug]))
    #
    # Results live only in the shared SnapDiff::AI store -- the HTML
    # reporter annotates from it, gate reads it, no files, no wiring.
    # Extension: SnapDiff::AI.register(:name) { backend } -- no edits here.
    class AISimple
      # fail_on: verdicts that still fail the test; every other verdict
      # suppresses the pixel diff. "unknown" ALWAYS fails -- AI can
      # downgrade a diff, never vouch for one it could not classify.
      # nil thresholds defer to AI.verdict's defaults -- one source of truth.
      def initialize(backend: nil, flaky: nil, intentional: nil, fail_on: nil)
        @thresholds = {flaky: flaky, intentional: intentional}.compact
        @backend = resolve(backend)
        @fail_on = Array(fail_on).map(&:to_s) if fail_on
        # Memoized per COMPARISON AND INPUTS: the gate at validate-time
        # and the reporter pass at teardown see the same difference with
        # the same name and metrics; a reassigned compare, a mutated
        # result, or a later test asserting the same name all change the
        # key and re-analyze -- a stale "flaky" must never suppress a
        # fresh regression.
        @memo = {}
        @memo_mutex = Mutex.new
        # The one failure-gate slot in SnapDiff::Contributions -- core
        # consults it without knowing AI exists.
        Contributions.register_suppression(self) if @fail_on
      end

      # Analyze differing assertions and store their results, reusing gate-time analysis.
      # Do nothing when the backend is unavailable.
      def record(assertions)
        return unless @backend

        assertions.each do |a|
          difference = a.compare&.difference
          next unless difference&.different?

          analyze_once(a.name, difference)
        end
      end

      # Failure-gate contract (SnapDiff::Contributions), consulted by
      # ScreenshotAssertion#validate on a pixel diff, before the error
      # message is built. Analysis is memoized, so #record never
      # re-analyzes. Returns {source:, text:} to waive the failure,
      # nil to let it stand. "unknown" ALWAYS fails -- AI can downgrade
      # a diff, never vouch for one it could not classify.
      def suppress(name, difference)
        return unless @backend

        # nil analysis (the backend raised) -> the pixel failure stands.
        result = analyze_once(name, difference)
        return unless result

        {source: "ai", text: AI.format(result)} unless fails?(result[:verdict])
      end

      # Return whether a verdict must fail under the configured fail_on policy.
      # Unknown verdicts always fail; requires a reporter configured with fail_on.
      def fails?(verdict) = verdict == "unknown" || @fail_on.include?(verdict)

      # Results are already in the shared store -- nothing to write out.
      def finalize = nil

      def summary
        results = AI.results
        return if results.empty?

        counts = results.group_by { |r| r[:verdict] }.transform_values(&:size)
        breakdown = AI::VERDICTS.filter_map { |v| "#{counts[v]} #{v}" if counts[v] }
        "[snap_diff:ai] #{results.size} diff(s) analyzed: #{breakdown.join(", ")}"
      end

      # Fork-parallel (Rails parallelize): the shared store round-trips.
      def dump_state = AI.dump_state
      def merge_state!(state) = AI.merge_state!(state)

      private

      # Unknown names and invalid objects are config errors and raise;
      # a factory that fails to build (missing gem, init error) degrades
      # to a warning and disabled triage.
      def resolve(backend)
        AI.resolve(backend)
      rescue ArgumentError
        raise
      rescue LoadError => e
        warn "[snap_diff:ai] backend unavailable (#{e.message}) -- AI triage disabled."
        nil
      rescue => e
        warn "[snap_diff:ai] backend factory failed (#{e.class}: #{e.message}) -- AI triage disabled."
        nil
      end

      def analyze_once(name, difference)
        key = [difference.object_id, name, difference.to_h]
        result = @memo_mutex.synchronize do
          @memo.fetch(key) { @memo[key] = analyze(name, difference) }
        end
        AI.record_result(result) if result
        result
      end

      def analyze(name, difference)
        raw = @backend.call(
          name: name,
          base: difference.original_image_path&.to_s,
          current: difference.new_image_path&.to_s,
          meta: difference.to_h
        ).transform_keys(&:to_sym)

        # A backend's own :verdict outranks the shared thresholds, but
        # only known verdicts are honored -- anything else becomes
        # "unknown", which the fail-gate never suppresses.
        raw[:verdict] = AI.verdict(raw[:similarity], **@thresholds) if raw[:verdict].nil?
        raw[:verdict] = "unknown" unless AI::VERDICTS.include?(raw[:verdict])
        result = {name: name, backend: backend_name}.merge(raw.except(:name, :backend))
        log(result)
        result
      rescue => e
        warn "[snap_diff:ai] Backend failed for #{name.inspect} (#{e.class}: #{e.message})"
        nil
      end

      def backend_name
        @backend.respond_to?(:name) ? @backend.name : "custom"
      end

      def log(r)
        $stdout.puts "[snap_diff:ai] #{r[:name]}: #{AI.format(r)}"
        $stdout.puts "  pixels differ but semantics match -- candidate for skip_area or a tolerance bump" if r[:verdict] == "flaky"
      end
    end
  end
end
