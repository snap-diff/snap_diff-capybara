# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

module SnapDiff
  # Process-global reporter lifecycle: registration, per-test notification,
  # end-of-suite finalization. One list of reporters for the whole process,
  # guarded by one mutex.
  #
  # Deliberately separate from the per-test session lifecycle
  # (SnapDiff.session): reporters outlive any single test, the session does
  # not. CapybaraScreenshotDiff keeps its public
  # reporters/reporters_mutex/finalize_reporters! methods as thin shims
  # over this module.
  module Reporting
    @reporters = []
    @mutex = Mutex.new
    @missing_baselines = Set.new
    @rerecorded_baselines = Set.new

    class << self
      attr_reader :reporters, :mutex

      # Remembers a screenshot that had no COMMITTED baseline and was
      # therefore never compared.
      #
      # @return [Boolean] true the first time this name is seen -- the
      #   "warn once per screenshot" gate for ScreenshotMatcher, and the
      #   tally behind {finalize!}'s summary line. Kept here rather than in
      #   the matcher because the end-of-run summary is this module's job.
      def record_missing_baseline(name)
        @mutex.synchronize { !!@missing_baselines.add?(name) }
      end

      # How many screenshots were captured but never compared. The "new"
      # count on the end-of-run summary line, and live state: it is the
      # number of screenshots that actually went down the no-baseline path
      # this run, not a number derived from what the run should have done.
      def missing_baselines_count
        @mutex.synchronize { @missing_baselines.size }
      end

      # @api private
      # Per-test isolation for this gem's own suite.
      def reset_missing_baselines!
        @mutex.synchronize { @missing_baselines.clear }
      end

      # Remembers a screenshot re-recorded by `record: :all` -- captured as
      # the new baseline with nothing compared against it. A separate tally
      # from {record_missing_baseline} on purpose: "there was no baseline"
      # and "there was one and we accepted the new rendering over it" are
      # different facts, and the summary must not claim the first when the
      # second happened.
      def record_rerecorded_baseline(name)
        @mutex.synchronize { !!@rerecorded_baselines.add?(name) }
      end

      # @api private
      def reset_rerecorded_baselines!
        @mutex.synchronize { @rerecorded_baselines.clear }
      end

      # Registers a reporter for the rest of the process. The canonical way
      # in: the append happens under the mutex, so concurrent registrations
      # cannot lose one (issue #217 item 2). `reporters` stays public and
      # mutable for compatibility -- appending to it directly still works,
      # it just skips the lock.
      def register(reporter)
        @mutex.synchronize { @reporters << reporter }
        reporter
      end

      # Delivers a finished test's assertions to every registered reporter.
      # Iterates over a snapshot so a reporter mutating the list mid-notify
      # cannot affect the current round. A raising reporter is warned about
      # and skipped; the rest are still notified.
      def notify(assertions)
        return if assertions.nil? || assertions.empty?

        reporters_snapshot = @mutex.synchronize { @reporters.dup }
        return if reporters_snapshot.empty?

        reporters_snapshot.each do |reporter|
          reporter.record(assertions)
        rescue => e
          warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
        end
      end

      # End-of-suite hook: finalizes each reporter and prints its summary.
      # A raising reporter is warned about and skipped; the rest are still
      # finalized.
      def finalize!
        @mutex.synchronize { @reporters.dup }.each do |reporter|
          reporter.finalize
          if (msg = reporter.summary)
            $stdout.puts msg
          end
        rescue => e
          warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
        end

        if (msg = missing_baselines_summary)
          $stdout.puts msg
        end

        if (msg = rerecorded_baselines_summary)
          $stdout.puts msg
        end
      end

      # --- fork-parallel reports (issue #258) ---------------------------
      #
      # Under Rails' default `parallelize(workers: N)` the tests run in
      # forked children, and Minitest skips `after_run` in a forked child
      # (`allow_fork = false`, minitest.rb:64/79). So every worker holds
      # records and never finalizes, while the parent finalizes and holds
      # none: no report, no summary line. Pass/fail is unaffected -- the
      # failures marshal back over DRb -- which is what makes it quiet.
      #
      # Rails runs `run_cleanup_hooks` INSIDE the worker just before it
      # exits (parallelization/worker.rb:31), so each worker dumps its
      # records there, and the parent merges the fragments in the
      # `Minitest.after_run` it does reach.

      # Registers the worker-side dump with Rails, once per process.
      #
      # Feature-detected twice over: the gem must load without Rails at
      # all, and with `Bundler.require` it loads BEFORE
      # ActiveSupport::TestCase exists, so the caller retries from
      # `ActiveSupport.on_load`.
      #
      # @return [Boolean] true when the hook is registered (now or already)
      def install_parallel_hooks!
        return true if @parallel_owner_pid
        return false unless defined?(::ActiveSupport::Testing::Parallelization)

        @parallel_owner_pid = Process.pid
        ::ActiveSupport::Testing::Parallelization.run_cleanup_hook { dump_parallel_fragment }
        true
      end

      # Outside the repository on purpose: it holds run-scoped scratch, and
      # the alternative -- somewhere under `save_path` -- is a directory
      # users `git add`.
      #
      # Keyed by the pid recorded at install time, which happens in the
      # parent before any fork: `Process.pid` here would give each worker a
      # directory of its own that the parent never looks in.
      def parallel_fragments_dir
        File.join(Dir.tmpdir, "snap_diff-fragments-#{@parallel_owner_pid}")
      end

      # Worker side. Writes to a `.tmp` name and renames it into place, so
      # a worker killed mid-write leaves nothing the merge will read.
      def dump_parallel_fragment
        payload = {
          "missing_baselines" => @mutex.synchronize { @missing_baselines.to_a },
          "rerecorded_baselines" => @mutex.synchronize { @rerecorded_baselines.to_a },
          "reporters" => @mutex.synchronize { @reporters.dup }
            .map { |reporter| reporter.dump_state if reporter.respond_to?(:dump_state) }
        }

        FileUtils.mkdir_p(parallel_fragments_dir)
        tmp = File.join(parallel_fragments_dir, "#{Process.pid}.json.tmp")
        File.write(tmp, JSON.generate(payload))
        File.rename(tmp, File.join(parallel_fragments_dir, "#{Process.pid}.json"))
      end

      # Parent side, called just before {finalize!}. A no-op when nothing
      # forked, which is what keeps serial and `with: :threads` -- both of
      # which record in the process that finalizes -- exactly as they were.
      #
      # Reporters are matched by position: registration happens at require
      # time, before any fork, so the list is identical in every process.
      def merge_parallel_fragments!
        return unless @parallel_owner_pid == Process.pid

        Dir[File.join(parallel_fragments_dir, "*.json")].sort.each do |fragment|
          payload = JSON.parse(File.read(fragment))

          @mutex.synchronize { payload["missing_baselines"].each { |name| @missing_baselines << name } }
          # `to_a` on a fresh install predates this key: a fragment written
          # by an older worker has no "rerecorded_baselines" at all.
          @mutex.synchronize { payload.fetch("rerecorded_baselines", []).each { |name| @rerecorded_baselines << name } }

          reporters_snapshot = @mutex.synchronize { @reporters.dup }
          payload["reporters"].each_with_index do |state, index|
            reporter = reporters_snapshot[index]
            reporter.merge_state!(state) if state && reporter.respond_to?(:merge_state!)
          end
        end

        FileUtils.rm_rf(parallel_fragments_dir)
      end

      # The reporters' summary line carries the COUNT of screenshots that
      # were captured without a committed baseline ("N new (not
      # verified)"); this line names them, so the next thing the reader
      # does is `git add` the right files.
      #
      # @return [String, nil] nil when every screenshot had a baseline
      def missing_baselines_summary
        names = @mutex.synchronize { @missing_baselines.to_a }
        return if names.empty?

        label = (names.size == 1) ? "1 screenshot" : "#{names.size} screenshots"
        "[snap_diff] #{label} had no committed baseline and #{(names.size == 1) ? "was" : "were"} NOT compared: " \
          "#{names.join(", ")}. Commit the captured file(s) to enable comparison."
      end

      # The other half of "nothing was compared", and the louder one:
      # `record: :all` accepts whatever the page rendered as the new
      # baseline. Names the screenshots that really went down that path this
      # run, so `git add` lands on the right files -- and so nobody commits
      # forty accepted regressions without being told they were accepted.
      #
      # @return [String, nil] nil when nothing was re-recorded
      def rerecorded_baselines_summary
        names = @mutex.synchronize { @rerecorded_baselines.to_a }
        return if names.empty?

        label = (names.size == 1) ? "1 screenshot" : "#{names.size} screenshots"
        "[snap_diff] record: :all re-recorded #{label} WITHOUT comparing: #{names.join(", ")}. " \
          "Review the result before committing -- an unintended change is accepted just as silently."
      end
    end
  end
end
