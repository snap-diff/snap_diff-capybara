# frozen_string_literal: true

require "base64"
require "digest"
require "erb"
require "fileutils"
require "pathname"
require "json"
require "shellwords"
# The auto-registration block at the bottom of this file registers with
# SnapDiff::Reporting.
require "snap_diff/reporting"
require "snap_diff/config"
require "snap_diff/vcs"

module SnapDiff
  module Reporters
    class HTML
      # One entry per screenshot that was not a plain pass, each with a
      # `status` ("changed", "rerecorded" or "new") and, when the report
      # could not render it, an `error` beside it.
      attr_reader :entries, :total

      def initialize(output_path: nil, embed_images: false)
        @explicit_output_path = output_path
        @embed_images = embed_images
        @entries = []
        @new_names = Set.new
        @total = 0
        @finalized = false
        @mutex = Mutex.new
      end

      def record(assertions)
        return if @finalized

        entries = []
        total = 0

        assertions.each do |assertion|
          status = assertion.status
          entry = begin
            entry_for(assertion, status) unless status == :passed
          rescue => e
            # A report bug must not hide a screenshot: warn, and keep it
            # listed with the status it has and the error beside it. The
            # error says the report could not render it, not what became of
            # the screenshot.
            error = "#{e.class}: #{e.message}"
            warn "[snap_diff] HTML report: could not render '#{assertion.name}' (#{error})"
            {name: assertion.name, status: status.to_s, error: error}
          end

          total += 1 unless status == :new
          entries << entry if entry
        end

        @mutex.synchronize do
          return if @finalized
          @total += total
          add_entries(entries)
        end
      end

      def finalize
        @mutex.synchronize do
          return if @finalized
          return if entries.empty?

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
        @mutex.synchronize { {"total" => @total, "entries" => @entries} }
      end

      def merge_state!(state)
        @mutex.synchronize do
          @total += state.fetch("total")
          add_entries(state.fetch("entries").map { |entry| entry.transform_keys(&:to_sym) })
        end
      end

      # The entries that were compared and differed, and not accepted:
      # `:changed`. (Ones the report could not render keep their status.)
      def changed_entries = entries.select { |entry| entry[:status] == "changed" }

      def new_count = count_entries("new")
      def rerecorded_count = count_entries("rerecorded")

      # What the report shows as "changed", like the terminal summary: the
      # ones that differed, re-recorded included.
      def changed_count = changed_entries.size + rerecorded_count

      # Shipped names (2.0.0.beta4), kept as shims: what is "changed" here
      # was "failures" there, and the re-recorded ones are not part of it.
      def failures = changed_entries

      def failed = changed_entries.size

      def passed = total - changed_count

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
        ERB.new(File.read(self.class.template_path)).result(binding)
      end

      # Review controls (Accept/Reject, the PR comment command) exist only in
      # a CI run, where the run id names the artifact the bot reads.
      def review
        run = ENV["GITHUB_RUN_ID"].to_s
        return if run.empty?

        files = manifest_entries.map { |entry| entry[:accept]["file"] }
        {run: run, files: files, sha16: files.to_h { |file| [file, file_sha256(file)[0, 16]] }}
      end

      # The entries the page shows. In a CI run the manifest's entry for a
      # file (its last capture) carries that `file`; an earlier capture of the
      # same file points at it (`superseded_by`, an index); any other entry
      # says why it has no controls (`review_reason`). The rest of :accept
      # stays internal.
      def report_data
        in_review = review
        chosen = in_review ? manifest_entries : []
        entries.map do |entry|
          data = entry.except(:accept)
          next data unless in_review

          if chosen.any? { |m| m.equal?(entry) }
            data[:file] = entry[:accept]["file"]
          elsif reviewable_status?(entry) && captured?(entry)
            later = last_captures.find { |m| m[:accept]["path"] == entry[:accept]["path"] }
            data[:superseded_by] = entries.index { |e| e.equal?(later) }
          else
            data[:review_reason] = (entry[:status] == "rerecorded") ? "rerecorded" : "no_capture"
          end
          data
        end
      end

      def self.template_path
        File.expand_path("templates/report.html.erb", __dir__)
      end

      def self.default_output_path
        root = SnapDiff.config.root || Pathname.pwd
        root / SnapDiff.config.save_path / "snap_diff_report.html"
      end

      private

      # Under the mutex. A name with no baseline is one new screenshot
      # however many times it was captured (as Reporting counts it).
      def add_entries(entries)
        entries.each do |entry|
          next if entry[:status] == "new" && !@new_names.add?(entry[:name])

          @entries << entry
        end
      end

      def count_entries(status) = entries.count { |entry| entry[:status] == status }

      def entry_for(assertion, status)
        if status == :new
          new_screenshot_entry(assertion.name, assertion.path)
        else
          compared_entry_for(assertion.name, assertion.compare).merge(status: status.to_s)
        end
      end

      # Build a report entry from a comparison, omitting unavailable images and metrics.
      def compared_entry_for(name, compare)
        {
          name: name,
          original: resolve_image(compare.base_image_path),
          new: resolve_image(compare.image_path),
          accept: accept_paths(compare.image_path)
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
      # or annotate. The entry keeps its status (it was compared and differs)
      # and carries the error so the page says why there is nothing to show.
      # resolve_image already drops the missing file from original/new.
      def missing_input_details(compare)
        {error: compare.processed.error_message.lines.first.strip}
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
        entries.each do |entry|
          # ||= would create a nil :annotations key on misses; keep the
          # entry clean.
          annotations = SnapDiff::Contributions.annotations_for(entry[:name])
          entry[:annotations] ||= annotations unless annotations.empty?
        end
      end

      # The image and the `git add` are offered only for a file that is on
      # disk now (#260).
      def new_screenshot_entry(name, path)
        entry = {name: name, status: "new"}
        image = resolve_image(path)
        return entry unless image

        entry.merge(new: image, accept: accept_paths(path),
          git_add: "git add -- #{Shellwords.escape(display_path(path))}")
      end

      # Relative to the project root, where the user runs `git add` -- the
      # same form as the failure messages. Absolute when the file is outside
      # the root, where a relative path would mislead.
      def display_path(path)
        relative = Pathname(path).relative_path_from(SnapDiff.config.root).to_path
        relative.start_with?("..") ? path.to_s : relative
      end

      # For snap_diff_manifest.json: the capture overwrote the baseline, so it
      # is both what to commit (`path`, from the git root) and what the
      # artifact holds (`file`, from the report dir). String keys: entries
      # pass through JSON in dump_state.
      def accept_paths(capture)
        return unless capture && File.exist?(capture)

        git_root = SnapDiff::Vcs.git_root_for(SnapDiff.config.root.to_s)
        return unless git_root

        file = Pathname(capture).expand_path.relative_path_from(output_path.dirname.expand_path).to_s
        return if file.start_with?("..") # outside the report dir, so not in the artifact

        {"path" => Pathname(capture).realpath.relative_path_from(Pathname(git_root).realpath).to_s, "file" => file}
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

      # One digest per file for the page and the manifest alike.
      def write_report
        FileUtils.mkdir_p(output_path.dirname)
        @digests = {}
        File.write(output_path, render)
        write_manifest
      ensure
        @digests = nil
      end

      def reviewable_status?(entry) = %w[changed new].include?(entry[:status])

      def captured?(entry) = entry[:accept] && (output_path.dirname / entry[:accept]["file"]).file?

      # Of the bytes on disk when the report is written -- what the artifact
      # uploads. The accept command carries its first 16 hex digits, and the
      # bot refuses a file whose bytes no longer match.
      def file_sha256(file)
        digest = -> { Digest::SHA256.file(output_path.dirname / file).hexdigest }
        @digests ? (@digests[file] ||= digest.call) : digest.call
      end

      # One file, one entry: the last capture, whatever its status -- a changed
      # one re-recorded afterwards is already accepted.
      def last_captures
        entries.select { |entry| captured?(entry) }.reverse.uniq { |entry| entry[:accept]["path"] }.reverse
      end

      def manifest_entries = last_captures.select { |entry| reviewable_status?(entry) }

      # What a reviewer page may accept: the captures that differ or are new.
      def write_manifest
        manifest = manifest_entries.map do |entry|
          {"name" => entry[:name], "status" => entry[:status]}.merge(entry[:accept], "sha256" => file_sha256(entry[:accept]["file"]))
        end
        File.write(output_path.dirname / "snap_diff_manifest.json", JSON.pretty_generate("version" => 1, "entries" => manifest))
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
