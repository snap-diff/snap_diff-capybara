# frozen_string_literal: true

require "base64"
require "erb"
require "fileutils"
require "pathname"
require "json"
require "shellwords"
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
          counted = false
          compare = assertion.compare
          next unless compare

          total += 1
          counted = true
          next unless compare.difference&.different?

          failures << failure_entry_for(assertion.name, compare)
        rescue => e
          # A report bug must not hide a screenshot: warn, and keep it listed
          # (counted as failed: the report can't vouch for it).
          error = "#{e.class}: #{e.message}"
          warn "[snap_diff] HTML report: could not render '#{assertion.name}' (#{error})"
          total += 1 unless counted
          failures << {name: assertion.name, error: error}
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
          return if failures.empty? && new_count.zero?

          write_report
          @finalized = true
          output_path
        end
      end

      def output_path
        @output_path ||= Pathname.new(@explicit_output_path || self.class.default_output_path)
      end

      # Fork-parallel handoff (issue #258). A forked worker never reaches
      # `Minitest.after_run`, so it hands its records to the parent as
      # plain data instead. JSON on purpose -- boring, and a half-written
      # file is discarded rather than half-read. Image paths were resolved
      # against `output_path`, which is the same in both processes.
      def dump_state
        @mutex.synchronize { {"total" => @total, "failures" => @failures} }
      end

      def merge_state!(state)
        @mutex.synchronize do
          @total += state["total"]
          @failures.concat(state["failures"].map { |entry| entry.transform_keys(&:to_sym) })
        end
      end

      def passed = total - failures.size
      def failed = failures.size
      # Screenshots captured but not compared: new ones are listed,
      # re-recorded ones only counted.
      def new_screenshots = SnapDiff::Reporting.uncompared.select { |screenshot| screenshot.reason == :new }
      def new_count = new_screenshots.size
      def rerecorded_count = SnapDiff::Reporting.uncompared.size - new_count

      # Both customer personas named this path as the best output in the
      # product, so it gets its own line -- but only when a report was
      # actually written.
      #
      # The counts this used to carry moved to SnapDiff::Reporting (issue
      # #269): they are printed for every user, and this file is not. See
      # Reporting.counts_summary.
      #
      # @return [String, nil] nil when no report was written
      def summary
        "[snap_diff] Report: #{output_path}" if @finalized
      end

      # Attach available contributions and return the rendered HTML report.
      def render
        attach_annotations
        @entries = failures + new_screenshot_entries
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

      # Build a report entry from a comparison, omitting unavailable images and metrics.
      def failure_entry_for(name, compare)
        {
          name: name,
          original: resolve_image(compare.base_image_path),
          new: resolve_image(compare.image_path)
        }.merge(failure_details(compare)).compact
      end

      def failure_details(compare)
        if compare.difference.failed_by&.[](:missing_image)
          missing_input_details(compare)
        elsif compare.dimensions_changed?
          dimension_change_details(compare)
        else
          difference_details(compare)
        end
      end

      # An input that vanished before the comparison leaves nothing to diff
      # or annotate. The entry carries the error so the page says so, instead
      # of inferring "pass" from the absent diff keys. resolve_image already
      # drops the missing file from original/new.
      def missing_input_details(compare)
        {error: compare.error_message.lines.first.strip}
      end

      # Images of different sizes get no annotated or heatmap images, and
      # no region metrics. Any annotated images on disk for this name are
      # left over from an earlier same-size failure, so they are not linked.
      def dimension_change_details(compare)
        {dimensions_changed: compare.reporter.dimension_change}
      end

      def difference_details(compare)
        difference = compare.difference
        {
          base_diff: resolve_image(compare.reporter.annotated_base_image_path),
          diff: resolve_image(compare.reporter.annotated_image_path),
          heatmap: resolve_image(compare.reporter.heatmap_diff_path),
          diff_level: difference.ratio && (difference.ratio * 100).round(2),
          area_size: difference.region_area_size,
          max_color_distance: difference.meta[:max_color_distance]&.round(1)
        }
      end

      # Contributed annotations (AI triage, ...), attached at RENDER
      # time: HTML records before contributing reporters
      # (auto-registration runs first) and fork-parallel merges land
      # after record, so only the final render can see everything.
      # HTML never names a contributor -- it renders whatever
      # SnapDiff::Contributions returns, empty by default.
      def attach_annotations
        failures.each do |entry|
          # ||= would create a nil :annotations key on misses; keep the
          # entry clean.
          annotations = SnapDiff::Contributions.annotations_for(entry[:name])
          entry[:annotations] ||= annotations unless annotations.empty?
        end
      end

      # Built at render time: the image and the `git add` are offered only
      # for a file that is on disk now (#260).
      def new_screenshot_entries
        new_screenshots.map { |screenshot| new_screenshot_entry(screenshot.name, screenshot.path) }
      end

      def new_screenshot_entry(name, path)
        entry = {name: name, new_screenshot: true}
        image = resolve_image(path)
        return entry unless image

        entry.merge(new: image, git_add: "git add -- #{Shellwords.escape(display_path(path))}")
      end

      # Relative to the project root, where the user runs `git add` -- the
      # same form as the failure messages. Absolute when the file is outside
      # the root, where a relative path would mislead.
      def display_path(path)
        relative = Pathname(path).relative_path_from(SnapDiff.config.root).to_path
        relative.start_with?("..") ? path.to_s : relative
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
  SnapDiff::Reporting.register(SnapDiff::Reporters::HTML.new(embed_images: SnapDiff::Config.ci?))
end
