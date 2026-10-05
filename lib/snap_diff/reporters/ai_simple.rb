# frozen_string_literal: true

require "json"
require "fileutils"

require "snap_diff/ai"
require "snap_diff/config"

module SnapDiff
  module Reporters
    # Advisory AI triage: classifies every FAILED comparison as
    # flaky/intentional/real_bug, logs one line per diff, writes
    # ai_report.json at finalize. By default never changes pass/fail;
    # with fail_on: the AI verdict gates the failure instead.
    #
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new)           # offline CLIP
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: :jev))
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: my_backend))
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(fail_on: %w[real_bug]))
    #
    # Results go into the shared SnapDiff::AI store, so the HTML reporter
    # annotates them automatically -- no wiring between the two.
    # Extension: SnapDiff::AI.register(:name) { backend } -- no edits here.
    class AISimple
      REPORT_FILENAME = "ai_report.json"

      # fail_on: verdicts that still fail the test; every other verdict
      # suppresses the pixel diff. "unknown" ALWAYS fails -- AI can
      # downgrade a diff, never vouch for one it could not classify.
      # nil thresholds defer to AI.verdict's defaults -- one source of truth.
      def initialize(backend: nil, flaky: nil, intentional: nil, output_path: nil, fail_on: nil)
        @thresholds = {flaky: flaky, intentional: intentional}.compact
        @output_path = output_path
        @backend = resolve(backend)
        @fail_on = Array(fail_on).map(&:to_s) if fail_on
        AI.gate = self if @fail_on
      end

      def record(assertions)
        return unless @backend

        assertions.each do |a|
          difference = a.compare&.difference
          next unless difference&.different?

          analyze_once(a.name, difference)
        end
      end

      # Fail-gate entry point, called by ScreenshotAssertion#validate on a
      # pixel diff. Analysis runs there (before the error message is
      # built) and is memoized, so #record never re-analyzes.
      def gated_result(name, difference)
        return unless @fail_on && @backend

        analyze_once(name, difference)
      end

      def fails?(verdict) = verdict == "unknown" || @fail_on.include?(verdict)

      def finalize
        results = AI.results
        return if results.empty?

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(results))
      end

      def summary
        results = AI.results
        return if results.empty?

        counts = results.group_by { |r| r[:verdict] }.transform_values(&:size)
        breakdown = %w[real_bug intentional flaky unknown].filter_map { |v| "#{counts[v]} #{v}" if counts[v] }
        "[snap_diff:ai] #{results.size} diff(s) analyzed: #{breakdown.join(", ")} (#{REPORT_FILENAME})"
      end

      # Fork-parallel (Rails parallelize): the shared store round-trips.
      def dump_state = AI.dump_state
      def merge_state!(state) = AI.merge_state!(state)

      private

      def resolve(backend)
        AI.resolve(backend)
      rescue LoadError => e
        warn "[snap_diff:ai] backend unavailable (#{e.message}) -- AI triage disabled."
        nil
      end

      def analyze_once(name, difference)
        AI[name] || analyze(name, difference)&.tap { |r| AI.record_result(r) }
      end

      def analyze(name, difference)
        raw = @backend.call(
          name: name,
          base: difference.original_image_path&.to_s,
          current: difference.new_image_path&.to_s,
          meta: difference.to_h
        ).transform_keys(&:to_sym)

        # A backend's own :verdict outranks the shared thresholds.
        raw[:verdict] ||= AI.verdict(raw[:similarity], **@thresholds)
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

      def output_path
        @output_path ||= File.join(SnapDiff.config.screenshot_area_abs.to_s, REPORT_FILENAME)
      end
    end
  end
end
