# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/html"
require "unit/gem_name_entry_point_test" # single source of truth for the Rails-less probe

# Rails' default `parallelize(workers: N)` forks, and Minitest skips
# `after_run` in a forked child (`allow_fork = false`). So the workers that
# hold every record never finalize, and the parent that finalizes recorded
# nothing: no HTML report, no summary line, on a suite that passes and fails
# exactly as it should otherwise.
#
# The fix has two halves and this file guards both, by forking for real and
# calling the same hook Rails calls inside the worker
# (`Parallelization.run_cleanup_hooks`, worker.rb:31):
#
#   worker -> dumps its records to a fragment file keyed by pid
#   parent -> merges every fragment before finalizing, then removes them
class ParallelReportMergeTest < ActiveSupport::TestCase
  include DSLStub

  setup do
    @output_dir = Pathname.new(Dir.mktmpdir)
    @output_path = @output_dir / "report.html"
    @original_reporters = SnapDiff::Reporting.reporters.dup
    @reporter = SnapDiff::Reporters::HTML.new(output_path: @output_path)
    SnapDiff::Reporting.reporters.replace([@reporter])
    # Deliberately NOT installing the hooks here: this suite requires
    # snap_diff/integrations/minitest BEFORE ActiveSupport::TestCase exists
    # -- exactly what `Bundler.require` does in a Rails app -- so every fork
    # below is also a check that the deferred `ActiveSupport.on_load`
    # install fires. Registering it here would hide that.
  end

  teardown do
    SnapDiff::Reporting.reporters.replace(@original_reporters)
    FileUtils.remove_entry(@output_dir) if @output_dir.exist?
    FileUtils.rm_rf(SnapDiff::Reporting.parallel_fragments_dir)
  end

  # Through `Reporting.notify`, the real path: a worker has to hand back BOTH
  # halves -- the reporter's records and the counts Reporting keeps itself
  # (issue #269) -- or the merged run is wrong in exactly the case this whole
  # file is about.
  test "records and counts from forked workers reach the parent" do
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("worker_a")]) }
    fork_worker do
      # Compared, new and re-recorded captures ride the same fragment
      # (#274 + #269): written by the same worker, merged by the same
      # parent, and none may cost the others.
      SnapDiff::Reporting.notify([
        build_failing_assertion("worker_b"), build_passing_assertion("worker_b_ok"),
        build_uncompared_assertion("worker_b_new", :new), build_uncompared_assertion("worker_b_accepted", :rerecorded)
      ])
    end

    # The bug, restated as an assertion: the parent holds nothing of its own.
    assert_equal 0, @reporter.total
    assert_equal 0, SnapDiff::Reporting.verified

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 3, @reporter.total
    assert_equal 2, @reporter.failed
    # The counts line must total the MERGED runs -- one worker's numbers
    # would be wrong here.
    assert_equal "[snap_diff] 3 verified, 2 changed, 1 new (not verified). 1 re-recorded (not verified).",
      SnapDiff::Reporting.counts_summary
    assert_includes SnapDiff::Reporting.rerecorded_baselines_summary, "worker_b_accepted"
    assert_equal [["worker_b_new", :new], ["worker_b_accepted", :rerecorded]],
      SnapDiff::Reporting.uncompared.map { |row| [row.name, row.status] }

    # Symbol keys, like an entry recorded in this process: `failures` is
    # public, and an array whose shape depends on which process filled it
    # is a trap for anything that reads it.
    assert_equal ["worker_a", "worker_b"], @reporter.failures.map { |failure| failure[:name] }.sort

    @reporter.finalize

    assert_predicate @output_path, :exist?
    assert_equal "[snap_diff] Report: #{@output_path}", @reporter.summary
  end

  # A new screenshot is tallied in the worker that captured it; the report
  # is written by the parent. It crosses the fork with the run's counts,
  # path included, or the parent lists nothing.
  test "a new screenshot captured in a worker is in the parent's report" do
    capture = @output_dir / "screenshots" / "signup.png"
    fork_worker do
      capture.dirname.mkpath
      FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), capture)
      SnapDiff::Reporting.notify([build_uncompared_assertion("signup", :new, path: capture)])
    end

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_includes SnapDiff::Reporting.counts_summary, "1 new (not verified)"
    assert_equal [{name: "signup", path: capture, status: :new}], SnapDiff::Reporting.uncompared.map(&:to_h)
    assert_predicate @reporter.finalize, :present?, "a run with only new screenshots writes a report"
    assert_includes @output_path.read, %("name":"signup","new_screenshot":true)
    assert_includes @output_path.read, "git add -- "
  end

  test "a re-recorded screenshot captured in a worker reaches the parent with its path" do
    fork_worker { SnapDiff::Reporting.notify([build_uncompared_assertion("accepted", :rerecorded, path: "/app/accepted.png")]) }

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal [{name: "accepted", path: Pathname("/app/accepted.png"), status: :rerecorded}],
      SnapDiff::Reporting.uncompared.map(&:to_h)
  end

  # The summary line counts names, merged across workers; the report must
  # list the same number.
  test "a new screenshot two workers both captured is listed once" do
    2.times { fork_worker { SnapDiff::Reporting.notify([build_uncompared_assertion("signup", :new, path: "/app/signup.png")]) } }

    SnapDiff::Reporting.merge_parallel_fragments!
    @reporter.finalize

    assert_includes SnapDiff::Reporting.counts_summary, "1 new (not verified)"
    assert_equal 1, @output_path.read.scan(%("name":"signup")).size
  end

  # The selector tally (#277b) is a RUN-level fact, and under fork-parallel
  # no single worker sees the run. The case that matters is the split
  # verdict: `img` matched in one worker and missed in another, so it is
  # doing its job and must NOT be named -- even though the worker that
  # missed reports it as unmatched. A merge that carried only the misses
  # would accuse it.
  test "a selector that matched in ANY worker is not accused after the merge" do
    fork_worker do
      SnapDiff::Reporting.record_selector_use("img", matched: true)
      SnapDiff::Reporting.record_selector_use("picture", matched: false)
    end
    fork_worker do
      SnapDiff::Reporting.record_selector_use("img", matched: false)
      SnapDiff::Reporting.record_selector_use("picture", matched: false)
    end

    assert_nil SnapDiff::Reporting.never_matched_selectors_summary

    SnapDiff::Reporting.merge_parallel_fragments!

    summary = SnapDiff::Reporting.never_matched_selectors_summary

    assert_includes summary, "1 selector never matched"
    assert_includes summary, "picture"
    refute_includes summary, "img"
  end

  # The stabilisation evidence (#271) is a run-level fact too, and Rails'
  # default `parallelize` is where a run-level line goes missing (#269).
  # Counts add up across workers; the WORST case does not -- the slowest
  # page in the run is the slowest page in whichever worker ran it.
  test "the worst stabilisation across workers survives the merge" do
    fork_worker { SnapDiff::Reporting.record_stable_capture(0.10, 2) }
    fork_worker { SnapDiff::Reporting.record_stable_capture(0.20, 2) }
    # The worst case is held by the PARENT here, not by a worker, and the
    # fragments are merged in filename order. Assigning instead of maxing
    # would clobber it whichever way the pids happened to sort -- an
    # order-dependent fixture let exactly that mutation through once.
    SnapDiff::Reporting.record_stable_capture(0.90, 5)

    SnapDiff::Reporting.merge_parallel_fragments!

    summary = SnapDiff::Reporting.stable_captures_summary

    assert_includes summary, "3 screenshots"
    assert_includes summary, "0.90s"
    assert_includes summary, "5 attempts"
    refute_includes summary, "settled on its first retry"
  end

  test "the parent removes the fragments it merged" do
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("cleaned")]) }

    assert_predicate Pathname.new(SnapDiff::Reporting.parallel_fragments_dir), :exist?

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_not Pathname.new(SnapDiff::Reporting.parallel_fragments_dir).exist?
  end

  # A worker killed mid-write must not corrupt the merge. Fragments are
  # written to a `.tmp` name and renamed into place, so a partial file never
  # carries the name the merge globs for.
  test "a fragment left half-written by a dead worker is ignored" do
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("survivor")]) }

    dir = SnapDiff::Reporting.parallel_fragments_dir
    File.write(File.join(dir, "99999.json.tmp"), '{"counts":{"passed')

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 1, @reporter.total
    assert_equal 0, SnapDiff::Reporting.missing_baselines_count
  end

  # A fragment is what the worker tallied (one counts hash, one row per
  # listed screenshot) and nothing derived from it: the parent sums the
  # counts and gets its "new" count from the merged rows.
  test "a fragment carries the status counts and the listed rows, and merging sums them" do
    2.times do |i|
      fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("changed_#{i}"), build_passing_assertion("ok_#{i}")]) }
    end

    payloads = Dir[File.join(SnapDiff::Reporting.parallel_fragments_dir, "*.json")].map { |file| JSON.parse(File.read(file)) }
    assert_equal [{"passed" => 1, "changed" => 1}] * 2, payloads.map { |payload| payload["counts"] }
    assert_empty payloads.flat_map(&:keys) & %w[verified changed missing_baselines rerecorded_baselines]

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal [4, 2], [SnapDiff::Reporting.verified, SnapDiff::Reporting.changed]
  end

  # Both uncompared statuses in one run, from different workers: neither may
  # swallow the other's count or its row.
  test "a new and a re-recorded screenshot from different workers keep their own counts and rows" do
    fork_worker { SnapDiff::Reporting.notify([build_uncompared_assertion("fresh", :new, path: "/app/fresh.png")]) }
    fork_worker { SnapDiff::Reporting.notify([build_uncompared_assertion("accepted", :rerecorded, path: "/app/accepted.png")]) }

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal "[snap_diff] 0 verified, 0 changed, 1 new (not verified). 1 re-recorded (not verified).",
      SnapDiff::Reporting.counts_summary
    assert_equal [["fresh", :new], ["accepted", :rerecorded]],
      SnapDiff::Reporting.uncompared.map { |row| [row.name, row.status] }
    assert_includes SnapDiff::Reporting.missing_baselines_summary, "fresh"
    assert_includes SnapDiff::Reporting.rerecorded_baselines_summary, "accepted"
  end

  # A status nobody writes is a bug, and it fails loudly instead of being
  # guessed at.
  test "an outcome with an unknown status fails the merge loudly" do
    dir = SnapDiff::Reporting.parallel_fragments_dir
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("current")]) }
    File.write(File.join(dir, "99997.json"), JSON.generate({
      "outcomes" => [{"name" => "signup", "path" => nil, "status" => "bogus"}]
    }))

    error = assert_raises(ArgumentError) { SnapDiff::Reporting.merge_parallel_fragments! }
    assert_includes error.message, "bogus"
  ensure
    FileUtils.rm_rf(dir)
  end

  # The fragments directory is keyed by the parent's pid, and only a
  # successful merge removes it. A run killed before that leaves its
  # fragments behind, and a later run whose pid is recycled would merge
  # them: counts from a run that is not this one, or -- for a fragment in an
  # older shape -- a KeyError in `after_run` that costs the whole summary.
  # Installing the hooks happens in the parent before any fork, so that is
  # where the directory starts out empty.
  test "a fragment left behind by an earlier run never reaches the merge" do
    skip "Rails' fork-parallel mode needs Kernel#fork, which #{RUBY_ENGINE} does not implement" unless Process.respond_to?(:fork)

    owner = SnapDiff::Reporting.instance_variable_get(:@parallel_owner_pid)
    hooks = ActiveSupport::Testing::Parallelization.run_cleanup_hooks
    hooks_before = hooks.size
    SnapDiff::Reporting.instance_variable_set(:@parallel_owner_pid, Process.pid)
    dir = SnapDiff::Reporting.parallel_fragments_dir
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "99998.json"), JSON.generate({"verified" => 7, "changed" => 7}))
    SnapDiff::Reporting.instance_variable_set(:@parallel_owner_pid, nil)

    assert SnapDiff::Reporting.install_parallel_hooks!
    assert_empty Dir[File.join(dir, "*.json")], "installing the hooks starts the run with an empty directory"

    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("this_run")]) }
    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal [1, 1], [SnapDiff::Reporting.verified, SnapDiff::Reporting.changed]
  ensure
    hooks.pop while hooks.size > hooks_before
    SnapDiff::Reporting.instance_variable_set(:@parallel_owner_pid, owner)
  end

  # Serial and `parallelize(with: :threads)` both record in the process that
  # finalizes; they never write a fragment, and the merge must leave them
  # exactly as they were.
  test "merging is a no-op when no worker ever forked" do
    SnapDiff::Reporting.notify([build_failing_assertion("serial")])

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 1, @reporter.total
    assert_equal 1, @reporter.failed
  end

  # The other half of "killed mid-write": the fragment is written under a
  # `.tmp` name and renamed into place, so an interrupted write leaves
  # nothing the merge will ever glob.
  test "a worker interrupted mid-write leaves no fragment behind" do
    # IO.write, not File.write: File.write is the stubbed method below.
    partial_write = lambda do |path, content|
      IO.write(path, content[0, 10])
      raise Interrupt
    end

    File.stub(:write, partial_write) do
      assert_raises(Interrupt) { SnapDiff::Reporting.dump_parallel_fragment }
    end

    assert_empty Dir[File.join(SnapDiff::Reporting.parallel_fragments_dir, "*.json")]
  end

  # `parallelize_teardown { SnapDiff::Reporting.finalize! }` -- the manual
  # workaround docs/reporters.md used to prescribe -- runs in the worker.
  # Merging there would delete the other workers' fragments before the
  # parent ever sees them.
  test "a worker that finalizes does not consume the parent's fragments" do
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("kept")]) }

    pid = fork do
      SnapDiff::Reporting.merge_parallel_fragments!
      exit!(0)
    end
    Process.waitpid(pid)

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 1, @reporter.total
  end

  # The gem must keep loading in a bundle without Rails: an unconditional
  # reference to ActiveSupport::Testing::Parallelization breaks every
  # non-Rails Capybara user at require time.
  test "the Minitest integration loads with no ActiveSupport in sight" do
    out, err, status = GemNameEntryPointTest.probe(<<~'RUBY')
      require "snap_diff/integrations/minitest"
      puts "ACTIVESUPPORT:#{!defined?(ActiveSupport).nil?}"
      puts "ASSERTIONS:#{!defined?(SnapDiff::Minitest::Assertions).nil?}"
    RUBY

    assert_predicate status, :success?, "loading without Rails must not fail:\n#{out}\n#{err}"
    assert_includes out, "ACTIVESUPPORT:false", "the probe proves nothing if Rails is loaded"
    assert_includes out, "ASSERTIONS:true"
  end

  test "installing the hooks twice registers one cleanup hook" do
    before = ActiveSupport::Testing::Parallelization.run_cleanup_hooks.size

    assert SnapDiff::Reporting.install_parallel_hooks!
    assert_equal before, ActiveSupport::Testing::Parallelization.run_cleanup_hooks.size
  end

  private

  # Runs the block in a real forked child, then the exact hook Rails runs
  # inside a parallel worker before it exits.
  #
  # JRuby has no `fork` (`Process.respond_to?(:fork)` is false, and calling it
  # raises NotImplementedError), so Rails' fork-parallel mode -- the entire
  # subject of this file -- cannot happen there. JRuby suites parallelize with
  # threads, which record in the process that finalizes and are covered by
  # "merging is a no-op when no worker ever forked" above. Skipping is the
  # honest report: the behaviour is inapplicable, not untested.
  def fork_worker(&block)
    skip "Rails' fork-parallel mode needs Kernel#fork, which #{RUBY_ENGINE} does not implement" unless Process.respond_to?(:fork)

    pid = fork do
      block.call
      ActiveSupport::Testing::Parallelization.run_cleanup_hooks.each { |hook| hook.call(0) }
      exit!(0)
    end
    Process.waitpid(pid)
    assert_predicate $?, :success?
  end

  def build_passing_assertion(name)
    compare = make_comparison(:a, :a, destination: "pass_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end

  # A capture that was never compared: `:new`, or `:rerecorded` (`record:
  # :all`, which still discards the baseline).
  def build_uncompared_assertion(name, status, path: nil)
    SnapDiff::ScreenshotAssertion.new(name, path: path && Pathname(path), record_mode: (status == :rerecorded) ? :all : nil)
  end

  def build_failing_assertion(name)
    compare = make_comparison(:a, :b, destination: "fail_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end
end
