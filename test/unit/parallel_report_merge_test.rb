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
      SnapDiff::Reporting.notify([build_failing_assertion("worker_b"), build_passing_assertion("worker_b_ok")])
      SnapDiff::Reporting.record_missing_baseline("worker_b_new")
      # Rides the same fragment as the counts above (#274 + #269). Both
      # tallies are written by the same worker and merged by the same
      # parent, and neither may cost the other.
      SnapDiff::Reporting.record_rerecorded_baseline("worker_b_accepted")
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

    # Symbol keys, like an entry recorded in this process: `failures` is
    # public, and an array whose shape depends on which process filled it
    # is a trap for anything that reads it.
    assert_equal ["worker_a", "worker_b"], @reporter.failures.map { |failure| failure[:name] }.sort

    @reporter.finalize

    assert_predicate @output_path, :exist?
    assert_equal "[snap_diff] Report: #{@output_path}", @reporter.summary
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

  test "the parent removes the fragments it merged" do
    fork_worker { @reporter.record([build_failing_assertion("cleaned")]) }

    assert_predicate Pathname.new(SnapDiff::Reporting.parallel_fragments_dir), :exist?

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_not Pathname.new(SnapDiff::Reporting.parallel_fragments_dir).exist?
  end

  # A worker killed mid-write must not corrupt the merge. Fragments are
  # written to a `.tmp` name and renamed into place, so a partial file never
  # carries the name the merge globs for.
  test "a fragment left half-written by a dead worker is ignored" do
    fork_worker { @reporter.record([build_failing_assertion("survivor")]) }

    dir = SnapDiff::Reporting.parallel_fragments_dir
    File.write(File.join(dir, "99999.json.tmp"), '{"missing_baselines":["trunc')

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 1, @reporter.total
    assert_equal 0, SnapDiff::Reporting.missing_baselines_count
  end

  # The fragments directory is keyed by pid under the system temp dir, so a
  # recycled pid can hand this merge a fragment written by an older version
  # of the gem -- one with none of the keys added since. Every key but
  # "missing_baselines" is read with a default for exactly this.
  test "a fragment written before the newer tallies existed still merges" do
    fork_worker { SnapDiff::Reporting.notify([build_failing_assertion("current")]) }

    dir = SnapDiff::Reporting.parallel_fragments_dir
    File.write(File.join(dir, "99998.json"), JSON.generate({"missing_baselines" => ["ancient"], "reporters" => []}))

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 1, SnapDiff::Reporting.verified, "the current worker's counts survived the old fragment"
    assert_equal 1, SnapDiff::Reporting.missing_baselines_count
    assert_includes SnapDiff::Reporting.missing_baselines_summary, "ancient"
  end

  # Serial and `parallelize(with: :threads)` both record in the process that
  # finalizes; they never write a fragment, and the merge must leave them
  # exactly as they were.
  test "merging is a no-op when no worker ever forked" do
    @reporter.record([build_failing_assertion("serial")])

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
    fork_worker { @reporter.record([build_failing_assertion("kept")]) }

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
  def fork_worker(&block)
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

  def build_failing_assertion(name)
    compare = make_comparison(:a, :b, destination: "fail_#{name}")
    compare.processed

    SnapDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
  end
end
