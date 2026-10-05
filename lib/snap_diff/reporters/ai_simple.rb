# frozen_string_literal: true

require "json"
require "fileutils"

require "snap_diff/ai"
require "snap_diff/config"

module SnapDiff
  module Reporters
    # Advisory AI triage: classifies every FAILED comparison as
    # flaky/intentional/real_bug, logs one line per diff, writes
    # ai_report.json at finalize. Never changes pass/fail.
    #
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new)           # offline CLIP
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new(backend: :jev))
    #   SnapDiff::Reporting.register(SnapDiff::Reporters::AiSimple.new(backend: my_backend))
    #
    # Results go into the shared SnapDiff::Ai store, so the HTML reporter
    # annotates them automatically -- no wiring between the two.
    # Extension: SnapDiff::Ai.register(:name) { backend } -- no edits here.
    class AiSimple
      REPORT_FILENAME = "ai_report.json"

      def initialize(backend: nil, flaky: 0.985, intentional: 0.90, output_path: nil)
        @thresholds = {flaky: flaky, intentional: intentional}
        @output_path = output_path
        @backend = resolve(backend)
      end

      def record(assertions)
        return unless @backend

        assertions.each do |a|
          difference = a.compare&.difference
          next unless difference&.different?

          result = analyze(a.name, difference)
          Ai.record_result(result) if result
        end
      end

      def finalize
        results = Ai.results
        return if results.empty?

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, JSON.pretty_generate(results))
      end

      def summary
        results = Ai.results
        return if results.empty?

        counts = results.group_by { |r| r[:verdict] }.transform_values(&:size)
        breakdown = %w[real_bug intentional flaky unknown].filter_map { |v| "#{counts[v]} #{v}" if counts[v] }
        "[snap_diff:ai] #{results.size} diff(s) analyzed: #{breakdown.join(", ")} (#{REPORT_FILENAME})"
      end

      # Fork-parallel (Rails parallelize): the shared store round-trips.
      def dump_state = Ai.dump_state
      def merge_state!(state) = Ai.merge_state!(state)

      private

      def resolve(backend)
        Ai.resolve(backend)
      rescue LoadError => e
        warn "[snap_diff:ai] backend unavailable (#{e.message}) -- AI triage disabled."
        nil
      end

      def analyze(name, difference)
        raw = @backend.call(
          name: name,
          base: difference.original_image_path&.to_s,
          current: difference.new_image_path&.to_s,
          meta: difference.to_h
        ).transform_keys(&:to_sym)

        # A backend's own :verdict outranks the shared thresholds.
        raw[:verdict] ||= Ai.verdict(raw[:similarity], **@thresholds)
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
        line = "[snap_diff:ai:#{r[:backend]}] #{r[:name]}: #{r[:verdict].upcase}"
        line += " similarity=#{r[:similarity]}" if r[:similarity]
        line += " confidence=#{r[:confidence]}" if r[:confidence]
        line += " -- #{r[:summary]}" if r[:summary]
        $stdout.puts line
        $stdout.puts "  pixels differ but semantics match -- candidate for skip_area or a tolerance bump" if r[:verdict] == "flaky"
      end

      def output_path
        @output_path ||= File.join(SnapDiff.config.screenshot_area_abs.to_s, REPORT_FILENAME)
      end
    end
  end
end
