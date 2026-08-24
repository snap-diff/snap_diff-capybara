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
    @matched_selectors = Set.new
    @unmatched_selectors = Set.new
    @verified = 0
    @changed = 0
    @stable_captures = 0
    @worst_settle_seconds = 0.0
    @worst_settle_attempts = 0

    class << self
      attr_reader :reporters, :mutex

      # How many screenshots were compared to a committed baseline, and how
      # many of those differed.
      #
      # These counters live HERE, not in a reporter (issue #269). Counting
      # is core honesty; writing an HTML file is a feature. The summary
      # exists to catch the failure modes no per-assertion rule can see -- a
      # run where zero system tests executed, or where an inherited GIT_DIR
      # redirected every baseline lookup -- and `0 verified` is the only
      # signal for either. It shipped inside Reporters::HTML, the gem's one
      # and only `register` call site, so the documented Rails setup (which
      # requires just the Minitest integration) printed nothing at all.
      attr_reader :verified, :changed

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

      # Remembers whether a CSS selector (`skip_area`, `crop`) found
      # anything the one time it was resolved. Fed at the point of use, so
      # a selector that was configured but never reached cannot be named.
      #
      # Two sets rather than a counter: the question the summary answers is
      # "did this selector match ANYWHERE in the run", and under
      # fork-parallel the hits and the misses arrive from different
      # processes. Subtracting at read time is the only shape that survives
      # that merge (#266).
      def record_selector_use(selector, matched:)
        @mutex.synchronize do
          (matched ? @matched_selectors : @unmatched_selectors) << selector
        end
      end

      # Remembers what a capture that DID settle cost (#271).
      #
      # Only the worst case is kept, because that is the number the setting
      # has to cover: an average would suggest a `stability_time_limit` that
      # is too low for the slowest page in the suite.
      def record_stable_capture(seconds, attempts)
        @mutex.synchronize do
          @stable_captures += 1
          @worst_settle_seconds = seconds if seconds > @worst_settle_seconds
          @worst_settle_attempts = attempts if attempts > @worst_settle_attempts
        end
      end

      # @api private
      # Per-test isolation for this gem's own suite: everything {finalize!}
      # reports, cleared in one call. One surface rather than one reset per
      # tally, so a tally added later cannot be forgotten at the call site.
      def reset_run_totals!
        @mutex.synchronize do
          @missing_baselines.clear
          @rerecorded_baselines.clear
          @matched_selectors.clear
          @unmatched_selectors.clear
          @verified = 0
          @changed = 0
          @stable_captures = 0
          @worst_settle_seconds = 0.0
          @worst_settle_attempts = 0
        end
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

        # Warned about and skipped, never raised: `notify` runs inside every
        # test's teardown (SnapDiff.reset), and a raise here would abort the
        # reset before it clears the registry -- leaking one test's
        # assertions into the next. A tally must not be able to take a
        # user's suite down. Same contract the reporter loop below applies,
        # and just as loud: unconditional, not DEBUG-gated.
        begin
          count(assertions)
        rescue => e
          warn "[snap_diff] Could not tally the run (#{e.class}: #{e.message})"
        end

        reporters_snapshot = @mutex.synchronize { @reporters.dup }
        return if reporters_snapshot.empty?

        reporters_snapshot.each do |reporter|
          reporter.record(assertions)
        rescue => e
          warn "[snap_diff] Reporter #{reporter.class} failed (#{e.class}: #{e.message})"
        end
      end

      # Tallies a finished test's assertions. An assertion with no
      # `compare` never reached a baseline, so it is neither verified nor
      # changed -- it is counted, if at all, by {record_missing_baseline}.
      def count(assertions)
        verified = 0
        changed = 0

        assertions.each do |assertion|
          compare = assertion.compare
          next unless compare

          verified += 1
          changed += 1 if compare.difference&.different?
        end

        @mutex.synchronize do
          @verified += verified
          @changed += changed
        end
      end

      # The last line of the run, and the only place it says what it
      # actually did:
      #
      #   verified -- a committed baseline existed and was compared
      #   changed  -- of those, the ones that differed
      #   new      -- captured but NOT compared, for want of a committed
      #               baseline: neither a pass nor a failure
      #
      # Printed on every run, passing or failing, reporter or no reporter,
      # and never nil. "N screenshots compared" counted only what it
      # compared, so it was silent about exactly the screenshots it did not
      # -- and silent altogether when it compared nothing, which is the one
      # case worth shouting about.
      def counts_summary
        verified, changed, new_count, rerecorded = @mutex.synchronize {
          [@verified, @changed, @missing_baselines.size, @rerecorded_baselines.size]
        }
        line = "[snap_diff] #{verified} verified, #{changed} changed, #{new_count} new (not verified)."

        # `record: :all` (#274) accepts the rendering as the new baseline
        # without comparing, so those are neither verified nor changed --
        # and not "new" either, which is a different fact. Only shown when
        # it happened; the names are on their own line below.
        line += " #{rerecorded} re-recorded (not verified)." if rerecorded.positive?

        # The shout is for an UNEXPLAINED zero -- a suite that ran no system
        # tests, a GIT_DIR pointed at the wrong repository. Re-recording
        # explains it, and the user asked for it: shouting there is a false
        # alarm, and false alarms are how the real one stops being read.
        if verified.zero? && rerecorded.zero?
          return "#{line} NOTHING WAS VERIFIED -- no screenshot was compared to a committed baseline."
        end

        line
      end

      # End-of-suite hook: prints the counts, then finalizes each reporter
      # and prints its summary. A raising reporter is warned about and
      # skipped; the rest are still finalized -- and the counts line is
      # already out, so no reporter can take it down with it.
      def finalize!
        $stdout.puts counts_summary

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

        if (msg = never_matched_selectors_summary)
          $stdout.puts msg
        end

        if (msg = stable_captures_summary)
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
          # Both halves, not the subtraction: `img` may match in this worker
          # and miss in the next, and only the parent that merged every
          # fragment can tell whether it matched anywhere in the run.
          "matched_selectors" => @mutex.synchronize { @matched_selectors.to_a },
          "unmatched_selectors" => @mutex.synchronize { @unmatched_selectors.to_a },
          "verified" => @verified,
          "changed" => @changed,
          "stable_captures" => @stable_captures,
          "worst_settle_seconds" => @worst_settle_seconds,
          "worst_settle_attempts" => @worst_settle_attempts,
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

          # Only "missing_baselines" is read without a default: it is the
          # one key every version of this fragment has ever written. Every
          # key added since is `fetch`ed with one, because the fragments
          # directory is keyed by pid under the system temp dir -- a
          # recycled pid can hand this merge a fragment left behind by an
          # older version of the gem, and a partial payload must not take
          # the run down.
          @mutex.synchronize do
            payload["missing_baselines"].each { |name| @missing_baselines << name }
            payload.fetch("rerecorded_baselines", []).each { |name| @rerecorded_baselines << name }
            payload.fetch("matched_selectors", []).each { |selector| @matched_selectors << selector }
            payload.fetch("unmatched_selectors", []).each { |selector| @unmatched_selectors << selector }
            @verified += payload.fetch("verified", 0)
            @changed += payload.fetch("changed", 0)
            # Counts add up; worst cases do not -- the slowest page in the
            # run is the slowest page in whichever worker happened to run it.
            @stable_captures += payload.fetch("stable_captures", 0)
            @worst_settle_seconds = [@worst_settle_seconds, payload.fetch("worst_settle_seconds", 0.0)].max
            @worst_settle_attempts = [@worst_settle_attempts, payload.fetch("worst_settle_attempts", 0)].max
          end

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

      # The selectors that matched nothing in EVERY screenshot of the run.
      #
      # Since #272 a `skip_area` selector is resolved without waiting: it
      # masks what is on the page at assertion time, and one that matches
      # nothing produces an empty mask -- the unstable region is compared
      # and the test flakes, silently. #275 declined to warn per screenshot
      # because the gem cannot tell a typo from a legitimately image-less
      # page, and the legitimate case would fire on every screenshot.
      #
      # A run-level tally has no such problem. A selector that matched
      # SOMEWHERE is doing its job and is never mentioned; one that matched
      # NOWHERE, all run, is a typo or a stale selector with high
      # probability. Silent when the set is empty, on purpose: a line that
      # prints on every run is a line users learn to skip.
      #
      # @return [String, nil] nil when every selector used matched somewhere
      def never_matched_selectors_summary
        names = @mutex.synchronize { (@unmatched_selectors - @matched_selectors).to_a }
        return if names.empty?

        label = (names.size == 1) ? "1 selector" : "#{names.size} selectors"
        "[snap_diff] #{label} never matched anything in this run: " \
          "#{names.map(&:inspect).join(", ")}. " \
          "A selector that matches nothing masks nothing -- check for a typo or a stale selector."
      end

      # What waiting for the page to settle actually cost, on the runs where
      # it WORKED (#271).
      #
      # The failure path names the region that would not settle; this is the
      # other half. A maintainer who set `stability_time_limit: 2` on the
      # docs' recommendation has no way to learn their pages settle on the
      # first retry -- and without evidence, tuning it down is guesswork,
      # which loses to `sleep`. The measurement is free: the stable
      # screenshoter already knows both numbers at the moment it succeeds.
      #
      # Run-level rather than per-assertion, and silent when nothing waited:
      # the same reasoning as {never_matched_selectors_summary}. A line
      # printed on every screenshot of every run is a line users learn to
      # skip, and per-test noise is exactly what a debugging aid must not
      # add to a suite already too slow.
      #
      # @return [String, nil] nil when no capture waited for stability
      def stable_captures_summary
        captures, seconds, attempts = @mutex.synchronize {
          [@stable_captures, @worst_settle_seconds, @worst_settle_attempts]
        }
        return if captures.zero?

        label = (captures == 1) ? "1 screenshot" : "#{captures} screenshots"
        line = "[snap_diff] #{label} waited for the page to settle: " \
          "#{format("%.2f", seconds)}s and #{attempts} attempts at worst."

        # Two attempts is the floor -- one capture, then the retry that
        # matched it. Hitting the floor everywhere means no page in the run
        # was ever still moving, so every sleep between attempts was spent
        # on a page that had already stopped.
        if attempts <= 2
          line += " Every screenshot settled on its first retry, so a lower " \
            "stability_time_limit would cost less per screenshot."
        end

        line
      end
    end
  end
end
