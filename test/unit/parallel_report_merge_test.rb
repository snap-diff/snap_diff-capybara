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

  test "records from forked workers reach the parent's report and summary" do
    fork_worker { @reporter.record([build_failing_assertion("worker_a")]) }
    fork_worker do
      @reporter.record([build_failing_assertion("worker_b"), build_passing_assertion("worker_b_ok")])
      SnapDiff::Reporting.record_missing_baseline("worker_b_new")
    end

    # The bug, restated as an assertion: the parent holds nothing of its own.
    assert_equal 0, @reporter.total

    SnapDiff::Reporting.merge_parallel_fragments!

    assert_equal 3, @reporter.total
    assert_equal 2, @reporter.failed
    # The summary line must count the MERGED totals -- one worker's numbers
    # would be wrong in exactly the case this whole file is about.
    assert_equal "[snap_diff] 3 verified, 2 changed, 1 new (not verified). Report: #{@output_path}",
      @reporter.summary

    # Symbol keys, like an entry recorded in this process: `failures` is
    # public, and an array whose shape depends on which process filled it
    # is a trap for anything that reads it.
    assert_equal ["worker_a", "worker_b"], @reporter.failures.map { |failure| failure[:name] }.sort

    @reporter.finalize

    assert_predicate @output_path, :exist?
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
