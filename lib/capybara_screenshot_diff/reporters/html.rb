# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"
require "json"

module CapybaraScreenshotDiff
  module Reporters
    class HTML
      attr_reader :output_path, :failures, :total

      def initialize(output_path: "tmp/snap_diff-report/index.html")
        @output_path = Pathname.new(output_path)
        @report_dir = @output_path.dirname
        @failures = []
        @total = 0
      end

      def record(assertions)
        assertions.each do |assertion|
          compare = assertion.compare
          next unless compare

          @total += 1
          next unless compare.difference&.different?

          @failures << failure_entry_for(assertion.name, compare)
        rescue => e
          warn "[snap_diff] Reporter skipped '#{assertion.name}': #{e.message}"
        end
      end

      def finalize
        return if failures.empty?

        write_report
        $stdout.puts "[snap_diff] HTML report: #{output_path}"
      end

      def passed = total - failures.size
      def failed = failures.size

      def success_rate
        return 0 if total.zero?
        (passed.to_f / total * 100).round(1)
      end

      private

      def failure_entry_for(name, compare)
        {
          name: name,
          original: relative_path(compare.base_image_path),
          new: relative_path(compare.image_path),
          diff: relative_path(compare.reporter.annotated_image_path),
          heatmap: relative_path(compare.reporter.heatmap_diff_path)
        }
      end

      def relative_path(path)
        return "" unless path

        Pathname.new(path).relative_path_from(@report_dir).to_s
      rescue ArgumentError
        path.to_s
      end

      def write_report
        FileUtils.mkdir_p(@report_dir)
        File.write(output_path, ERB.new(File.read(template_path)).result(binding))
      end

      def template_path = File.expand_path("templates/report.html.erb", __dir__)
      def failed_screenshots = failures
    end
  end
end

unless CapybaraScreenshotDiff.reporters.any?(CapybaraScreenshotDiff::Reporters::HTML)
  CapybaraScreenshotDiff.reporters << CapybaraScreenshotDiff::Reporters::HTML.new
end

at_exit do
  CapybaraScreenshotDiff.reporters.each do |reporter|
    reporter.finalize
  rescue => e
    warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
    warn e.full_message(highlight: false) if e.respond_to?(:full_message)
  end
end
