# frozen_string_literal: true

require "base64"
require "erb"
require "fileutils"
require "pathname"
require "json"
# The auto-registration block at the bottom of this file registers with
# SnapDiff::Reporting.
require "snap_diff/reporting"
require "snap_diff/config"

module SnapDiff
  module Reporters
    class HTML
      attr_reader :failures, :total

      def initialize(output_path: nil, embed_images: false)
        @explicit_output_path = output_path
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
          return if failures.empty?

          write_report
          @finalized = true
          output_path
        end
      end

      def output_path
        @output_path ||= Pathname.new(@explicit_output_path || self.class.default_output_path)
      end

      def passed = total - failures.size
      def failed = failures.size

      def summary
        return if total.zero?

        screenshots_label = (total == 1) ? "1 screenshot" : "#{total} screenshots"

        if failures.empty?
          "[snap_diff] #{screenshots_label} compared, no failures."
        else
          failures_label = (failures.size == 1) ? "1 failure" : "#{failures.size} failures"
          "[snap_diff] #{screenshots_label} compared, #{failures_label}. Report: #{output_path}"
        end
      end

      def render
        ERB.new(File.read(self.class.template_path)).result(binding)
      end

      def self.template_path
        File.expand_path("templates/report.html.erb", __dir__)
      end

      def self.default_output_path
        root = SnapDiff.config.root || Pathname.pwd
        root / SnapDiff.config.save_path / "snap_diff_report.html"
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

        @embed_images ? data_uri(pathname) : pathname.relative_path_from(output_path.dirname.expand_path).to_s
      end

      def data_uri(pathname)
        ext = pathname.extname.delete_prefix(".")
        mime = (ext == "webp") ? "image/webp" : "image/png"
        "data:#{mime};base64,#{Base64.strict_encode64(pathname.binread)}"
      end

      def write_report
        FileUtils.mkdir_p(output_path.dirname)
        File.write(output_path, render)
      end
    end
  end
end

# Auto-register reporter.
# Framework adapters (Minitest, RSpec, Cucumber) call SnapDiff::Reporting.finalize! via native hooks.
# For custom frameworks, call SnapDiff::Reporting.finalize! manually.
unless SnapDiff::Reporting.reporters.any?(SnapDiff::Reporters::HTML)
  SnapDiff::Reporting.register(SnapDiff::Reporters::HTML.new(embed_images: !!ENV["CI"]))
end
