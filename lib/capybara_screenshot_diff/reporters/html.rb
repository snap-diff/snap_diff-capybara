# frozen_string_literal: true

require "erb"
require "fileutils"
require "pathname"
require "json"

module CapybaraScreenshotDiff
  module Reporters
    class HTML
      attr_reader :output_path, :failures, :total

      def initialize(output_path: "tmp/snap_diff/index.html")
        @output_path = Pathname.new(output_path)
        @report_dir = @output_path.dirname
        @failures = []
        @total = 0
        @finalized = false
      end

      def record(assertions)
        assertions.each do |assertion|
          compare = assertion.compare
          next unless compare

          @total += 1
          next unless compare.difference&.different?

          @failures << failure_entry_for(assertion.name, compare)
        rescue => e
          warn "[snap_diff] Reporter skipped '#{assertion.name}': #{e.message}" if ENV["DEBUG"]
        end
      end

      def finalize
        return if @finalized

        @finalized = true

        if failures.empty?
          warn "[snap_diff] No failures found, HTML report not generated" if ENV["DEBUG"]
          return
        end

        write_report
        true
      end

      def passed = total - failures.size
      def failed = failures.size

      def success_rate
        return 0 if total.zero?
        (passed.to_f / total * 100).round(1)
      end

      def render
        ERB.new(File.read(self.class.template_path)).result(binding)
      end

      def self.template_path
        File.expand_path("templates/report.html.erb", __dir__)
      end

      private

      def failure_entry_for(name, compare)
        difference = compare.difference
        {
          name: name,
          original: relative_path(compare.base_image_path),
          new: relative_path(compare.image_path),
          base_diff: relative_path(compare.reporter.annotated_base_image_path),
          diff: relative_path(compare.reporter.annotated_image_path),
          heatmap: relative_path(compare.reporter.heatmap_diff_path),
          diff_level: difference.ratio && (difference.ratio * 100).round(2),
          area_size: difference.region_area_size,
          max_color_distance: difference.meta[:max_color_distance]&.round(1)
        }
      end

      def relative_path(path)
        return unless path

        pathname = Pathname.new(path)
        return unless pathname.exist?

        pathname.relative_path_from(@report_dir).to_s
      end

      def write_report
        FileUtils.mkdir_p(@report_dir)
        File.write(output_path, render)
      end
    end
  end
end

unless CapybaraScreenshotDiff.reporters.any?(CapybaraScreenshotDiff::Reporters::HTML)
  CapybaraScreenshotDiff.reporters << CapybaraScreenshotDiff::Reporters::HTML.new
end

at_exit do
  CapybaraScreenshotDiff.reporters.each do |reporter|
    wrote = reporter.finalize
    $stdout.puts "[snap_diff] HTML report: #{reporter.output_path}" if wrote
  rescue => e
    warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})" if ENV["DEBUG"]
  end
end
