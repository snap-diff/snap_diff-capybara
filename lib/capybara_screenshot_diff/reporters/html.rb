# frozen_string_literal: true

require "base64"
require "erb"
require "fileutils"
require "pathname"
require "json"

module CapybaraScreenshotDiff
  module Reporters
    class HTML
      attr_reader :output_path, :failures, :total

      def initialize(output_path: "tmp/snap_diff/index.html", embed_images: false)
        @output_path = Pathname.new(output_path)
        @report_dir = @output_path.dirname
        @embed_images = embed_images
        @failures = []
        @total = 0
        @finalized = false
        @mutex = Mutex.new
      end

      def record(assertions)
        return if @finalized

        failures = []
        total = 0

        assertions.each do |assertion|
          compare = assertion.compare
          next unless compare

          total += 1
          next unless compare.difference&.different?

          failures << failure_entry_for(assertion.name, compare)
        rescue => e
          warn "[snap_diff] Reporter skipped '#{assertion.name}': #{e.message}" if ENV["DEBUG"]
        end

        @mutex.synchronize do
          return if @finalized
          @total += total
          @failures.concat(failures)
        end
      end

      def finalize
        @mutex.synchronize do
          return if @finalized

          @finalized = true
          return if failures.empty?

          write_report
          output_path
        end
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
          original: resolve_image(compare.base_image_path),
          new: resolve_image(compare.image_path),
          base_diff: resolve_image(compare.reporter.annotated_base_image_path),
          diff: resolve_image(compare.reporter.annotated_image_path),
          heatmap: resolve_image(compare.reporter.heatmap_diff_path),
          diff_level: difference.ratio && (difference.ratio * 100).round(2),
          area_size: difference.region_area_size,
          max_color_distance: difference.meta[:max_color_distance]&.round(1)
        }
      end

      def resolve_image(path)
        return unless path

        pathname = Pathname.new(path).expand_path
        return unless pathname.exist?

        @embed_images ? data_uri(pathname) : pathname.relative_path_from(@report_dir.expand_path).to_s
      end

      def data_uri(pathname)
        ext = pathname.extname.delete_prefix(".")
        mime = (ext == "webp") ? "image/webp" : "image/png"
        "data:#{mime};base64,#{Base64.strict_encode64(pathname.binread)}"
      end

      def write_report
        FileUtils.mkdir_p(@report_dir)
        File.write(output_path, render)
      end
    end
  end
end

# Auto-register reporter and at_exit hook.
# The reporter only writes when there are failures (finalize checks failures.empty?).
# Scripts that create their own reporter instance call record/finalize directly.
unless CapybaraScreenshotDiff.reporters.any?(CapybaraScreenshotDiff::Reporters::HTML)
  CapybaraScreenshotDiff.reporters << CapybaraScreenshotDiff::Reporters::HTML.new(embed_images: !!ENV["CI"])
end

at_exit do
  CapybaraScreenshotDiff.reporters.each do |reporter|
    result = reporter.finalize
    $stdout.puts "[snap_diff] HTML report: #{result}" if result.is_a?(Pathname)
  rescue => e
    warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})" if ENV["DEBUG"]
  end
end
