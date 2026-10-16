# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# Two concurrently-running tests asserting the SAME screenshot name race on
# one set of files: every artifact path derives from the name alone. One
# test's `archive_baseline!` moves the baseline the other test just checked
# out, and the loser's `need_to_compare?` then sees no baseline, records the
# screenshot as new, and returns without comparing. Green, having compared
# nothing (#217).
#
# "No baseline was ever committed" is a legitimate state with its own
# warning. "The baseline I just checked out has disappeared" is impossible
# in a correct run, and must be loud.
class BaselineDisappearedTest < ActiveSupport::TestCase
  include DSLStub

  # Stands in for the git checkout: writes a real baseline file the way a
  # successful `git show` would, so the disappearance is a real file going
  # away rather than a stubbed boolean flipping.
  def checking_out(fixture = "a.png")
    lambda do |_root, _screenshot_path, checkout_path|
      checkout_path.dirname.mkpath
      FileUtils.cp(File.expand_path(fixture, TEST_IMAGES_DIR), checkout_path)
      true
    end
  end

  # Deterministic version of the race: the baseline vanishes while the
  # screenshot is being captured, exactly as a concurrent
  # `archive_baseline!` would take it.
  def stealing_screenshoter
    Class.new(ScreenshoterStub) do
      define_method(:take_comparison_screenshot) do |snap|
        super(snap)
        snap.base_path.delete if snap.base_path.exist?
      end
    end
  end

  test "raises when a checked-out baseline disappears before the comparison" do
    name = "a_#{Time.now.nsec}"

    SnapDiff::Vcs.stub(:checkout_vcs, checking_out) do
      SnapDiff.config.stub(:screenshoter, stealing_screenshoter) do
        error = assert_raises(SnapDiff::Error) do
          SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
        end

        assert_match(/#{name}/, error.message)
        assert_match(/disappeared/i, error.message)
      end
    end

    assert_empty SnapDiff.session.assertions,
      "a vanished baseline must not be recorded as a never-committed one"
    assert_equal 0, SnapDiff::Reporting.missing_baselines_count,
      "nor counted as new, nor offered for `git add` in the report"
  end

  # The baseline can go between the checkout and the first look at it, too.
  def vanishing_checkout
    lambda do |root, screenshot_path, checkout_path|
      checking_out.call(root, screenshot_path, checkout_path)
      checkout_path.delete
      true
    end
  end

  # Whichever window the baseline vanishes in, and in either mode, it was
  # committed: the error says it disappeared (not "no baseline, git add
  # it"), no no-baseline warning, and nothing counted or listed as new.
  {"during the capture" => :stealing, "right after the checkout" => :vanishing}.each do |window, race|
    %i[once none].each do |mode|
      test "record: :#{mode}, a baseline that vanishes #{window} is reported as disappeared, not new" do
        SnapDiff.config.record = mode
        checkout = (race == :vanishing) ? vanishing_checkout : checking_out
        screenshoter = (race == :stealing) ? stealing_screenshoter : ScreenshoterStub

        error = nil
        _out, err = capture_io do
          SnapDiff::Vcs.stub(:checkout_vcs, checkout) do
            SnapDiff.config.stub(:screenshoter, screenshoter) do
              error = assert_raises(SnapDiff::Error) do
                SnapDiff::ScreenshotMatcher.new("a_#{Time.now.nsec}").build_screenshot_assertion
              end
            end
          end
        end

        assert_match(/disappeared/i, error.message)
        refute_match(/No committed baseline/, err)
        assert_equal 0, SnapDiff::Reporting.missing_baselines_count
        assert_empty SnapDiff.session.assertions
      ensure
        SnapDiff.config.record = nil
      end
    end
  end

  # The legitimate half of the distinction stays legitimate: no checkout
  # succeeded, so there is nothing to have disappeared.
  test "still records a new screenshot when no baseline was ever committed" do
    name = "a_#{Time.now.nsec}"

    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_equal :new, SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion.status
    end

    assert_includes SnapDiff.session.new_screenshots, name
  end

  # The session outlives the test -- Thread.current[] memoizes it for the
  # whole thread -- so the checkout record must not. Otherwise a name whose
  # baseline was read in one test raises in the next one, where having no
  # baseline is perfectly legitimate.
  test "SnapDiff.reset forgets which baselines were checked out" do
    name = "a_#{Time.now.nsec}"

    SnapDiff.session.record_baseline_checkout(name)
    SnapDiff.reset

    SnapDiff.session.record_new_screenshot(name)

    assert_includes SnapDiff.session.new_screenshots, name
  end

  # A capture that takes a little time, the way a real browser screenshot
  # does. The window this bug lives in is checkout -> capture ->
  # need_to_compare?, so an instant capture hides it.
  def slow_screenshoter
    Class.new(ScreenshoterStub) do
      define_method(:take_comparison_screenshot) do |snap|
        sleep(0.01)
        super(snap)
      end
    end
  end

  # The real thing: two threads, one name, no injected file deletion. The
  # loser's baseline is taken by the winner's archive_baseline!. Repeated
  # because it is a race -- the audit found it by running the harness ten
  # times. Any single silently-skipped comparison is the bug.
  test "concurrent tests on one screenshot name never skip a comparison silently" do
    rounds = Integer(ENV.fetch("RACE_ROUNDS", 20))
    name = "a_#{Time.now.nsec}"
    outcomes = Queue.new

    SnapDiff.config.stub(:screenshoter, slow_screenshoter) do
      SnapDiff::Vcs.stub(:checkout_vcs, checking_out) do
        # Free-running rather than barriered: the two tests must meet at
        # every phase offset, and it is the offset where one is archiving
        # while the other is still capturing that loses a comparison.
        threads = 2.times.map do |i|
          Thread.new do
            sleep(0.005 * i)
            rounds.times do
              outcomes << begin
                assertion = SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
                if assertion
                  assertion.validate
                  :compared
                else
                  :skipped
                end
              rescue SnapDiff::Error
                :raised
              rescue => e
                e.class
              ensure
                SnapDiff.reset
              end
            end
          end
        end

        threads.each(&:join)
      end
    end

    results = Array.new(outcomes.size) { outcomes.pop }
    tally = results.tally
    puts "[race] #{tally.inspect}"

    assert_equal 0, results.count(:skipped),
      "#{results.count(:skipped)} of #{results.size} comparisons were silently skipped (#{tally.inspect})"
  end
end
