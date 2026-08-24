# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# THE ACCEPT WORKFLOW (#259).
#
# Accepting an intentional UI change is the most frequent action in the
# product and until now it had no verb: users read vcs.rb to work out that
# the answer is `git add` + commit. `record:` is that verb, VCR-shaped --
# config, not a CLI flag, because there is no runner to hang a flag on.
#
#   :once  the default. Record when there is no committed baseline; compare
#          when there is. A RENAME of what the gem already did -- it adds no
#          branch, which is what makes "behaviour-identical to today" a
#          structural fact rather than a claim.
#   :none  strict. A missing baseline always fails, whatever `fail_if_new`
#          says.
#   :all   re-record. Every screenshot becomes the new baseline and nothing
#          is compared. THE BULK-ACCEPT VERB.
#
# PRECEDENCE, in one line: an explicitly set mode outranks `fail_if_new`,
# and `fail_if_new` is what decides when nothing was set. Same property
# #267 gave `fail_if_new` itself over the CI sniff -- explicit outranks
# implicit, all the way down.
class RecordModesTest < ActiveSupport::TestCase
  include SnapDiff::DSL
  include DSLStub

  def before_setup
    @original_root = SnapDiff.config.root
    @new_root = Dir.mktmpdir
    SnapDiff.config.root = Pathname.new(@new_root)
    super
  end

  def after_teardown
    super
    SnapDiff.config.root = @original_root
    FileUtils.remove_entry(@new_root) if @new_root
    SnapDiff::Reporting.reset_run_totals!
  end

  # --- the default is not touched --------------------------------------
  #
  # The missing-baseline default was researched and deliberately NOT
  # flipped: community precedent is CI-only failure. `record` reads back as
  # a real mode either way, so the matcher has one thing to branch on -- but
  # the answer with nothing set is exactly what `fail_if_new` already said.

  test "with nothing set, record mirrors fail_if_new -- :once off CI, :none on it" do
    SnapDiff.config.record = nil

    SnapDiff.config.fail_if_new = false
    assert_equal :once, SnapDiff.config.record

    SnapDiff.config.fail_if_new = true
    assert_equal :none, SnapDiff.config.record
  end

  # THE PRECEDENCE GUARD. Both surfaces set and disagreeing: the mode wins.
  test "an explicit record mode outranks fail_if_new in both directions" do
    SnapDiff.config.fail_if_new = true
    SnapDiff.config.record = :once
    assert_equal :once, SnapDiff.config.record

    SnapDiff.config.fail_if_new = false
    SnapDiff.config.record = :none
    assert_equal :none, SnapDiff.config.record
  end

  test "assigning nil hands the mode back to fail_if_new" do
    SnapDiff.config.fail_if_new = true
    SnapDiff.config.record = :once
    SnapDiff.config.record = nil

    assert_equal :none, SnapDiff.config.record
  end

  # --- :once ------------------------------------------------------------

  test ":once records a screenshot that has no committed baseline, and does not compare it" do
    SnapDiff.config.record = :once
    name = "c_#{Time.now.nsec}"

    capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        assert_nil SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_includes SnapDiff.session.new_screenshots, name
    assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?
  end

  # `record = :once` is the replacement for `fail_if_new = false`, so it has
  # to beat a `fail_if_new` that is on -- including the CI default.
  test ":once allows a new screenshot even where fail_if_new would have raised" do
    SnapDiff.config.fail_if_new = true
    SnapDiff.config.record = :once
    name = "c_#{Time.now.nsec}"

    capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        assert_nil SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?
  end

  test ":once compares against a committed baseline like it always did" do
    SnapDiff.config.record = :once

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)
      assertion = SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion

      assert_instance_of SnapDiff::ScreenshotAssertion, assertion
      assert_predicate assertion.compare, :different?
    end
  end

  # --- :none ------------------------------------------------------------

  test ":none fails on a missing baseline even with fail_if_new explicitly false" do
    SnapDiff.config.fail_if_new = false
    SnapDiff.config.record = :none
    name = "c_#{Time.now.nsec}"

    error = SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_raises(SnapDiff::ExpectationNotMet) do
        SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_includes error.message, SnapDiff::SnapManager.path_for(name).path.to_s
  end

  # #260, re-asserted for the mode that raises: the message says `git add
  # <path>`, so <path> has to be on disk by the time it is printed.
  test "the :none failure names a file that is really on disk and offers the record fix" do
    SnapDiff.config.record = :none
    name = "c_#{Time.now.nsec}"
    path = SnapDiff::SnapManager.path_for(name).path

    error = SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_raises(SnapDiff::ExpectationNotMet) do
        SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
      end
    end

    assert_predicate path, :exist?
    assert_includes error.message, "SnapDiff.config.record = :once"
  end

  test ":none does not also warn about the missing baseline" do
    SnapDiff.config.record = :none

    _out, err = capture_io do
      SnapDiff::Vcs.stub(:checkout_vcs, false) do
        assert_raises(SnapDiff::ExpectationNotMet) do
          SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}").build_screenshot_assertion
        end
      end
    end

    assert_no_match(/No committed baseline/, err)
  end

  # --- :all, the bulk-accept verb ---------------------------------------

  # THE ONE THAT MATTERS: a baseline exists AND differs, and :all accepts it.
  # Asserted on the BYTES on disk, not on the absence of an exception --
  # "no assertion was built" would also be true if the capture never ran.
  test ":all leaves the newly captured bytes on disk without comparing them" do
    SnapDiff.config.record = :all

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)

      assert_nil SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion

      assert_captured(:c, snap.path, "the re-recorded screenshot must be the new capture")
      assert_not_captured(:a, snap.path, "the old baseline must not survive a re-record")
      assert_not_predicate SnapDiff.session, :assertions_present?
    end
  end

  # :all does not ask git for a baseline -- there is nothing to compare
  # against. A `.base.<fmt>` from an earlier run would otherwise sit beside
  # the re-recorded screenshot and land in the user's `git add`.
  test ":all asks VCS for nothing and leaves no .base file behind" do
    SnapDiff.config.record = :all
    asked = []

    SnapDiff::Vcs.stub(:checkout_vcs, ->(*args) {
      asked << args
      true
    }) do
      snap = create_snapshot_for(:a, :c)
      SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion

      assert_empty asked, ":all must not spend a git process on a baseline it will not use"
      assert_not_predicate snap.base_path, :exist?
    end
  end

  test ":all never fails on a missing baseline, whatever fail_if_new says" do
    SnapDiff.config.fail_if_new = true
    SnapDiff.config.record = :all
    name = "c_#{Time.now.nsec}"

    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_nil SnapDiff::ScreenshotMatcher.new(name).build_screenshot_assertion
    end

    assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?
  end

  # What :all reports has to be what actually happened: the names that went
  # down the re-record path this run, and no others.
  test ":all summarises exactly the screenshots it re-recorded" do
    SnapDiff.config.record = :all
    names = nil

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      names = 3.times.map { create_snapshot_for(:a, :c).full_name }
      names.each { |n| SnapDiff::ScreenshotMatcher.new(n).build_screenshot_assertion }
    end

    summary = SnapDiff::Reporting.rerecorded_baselines_summary

    assert_match(/3 screenshots/, summary)
    names.each { |n| assert_includes summary, n }
    assert_match(/[Rr]eview/, summary, "accepting 3 baselines unreviewed is the thing to say out loud")
  end

  test "no re-record summary when nothing was re-recorded" do
    SnapDiff.config.record = :once

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff::ScreenshotMatcher.new(create_snapshot_for(:a, :c).full_name).build_screenshot_assertion
    end

    assert_nil SnapDiff::Reporting.rerecorded_baselines_summary
  end

  # --- :all is hard to trigger by accident ------------------------------
  #
  # Percy exits 0 when misconfigured, so a CI job that loses its token goes
  # green forever. `:all` accepts every rendering BY DESIGN, so left in a
  # committed config file it is exactly that failure: a build that compares
  # nothing and passes, with the "recorded" files thrown away with the box.
  # Refuse it under CI instead of building our own version of Percy.

  test ":all refuses to run under CI" do
    SnapDiff.config.record = :all

    error = with_ci("true") do
      assert_raises(SnapDiff::ExpectationNotMet) do
        SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}").build_screenshot_assertion
      end
    end

    assert_match(/record/, error.message)
    assert_match(/CI/, error.message)
  end

  test ":all runs off CI" do
    SnapDiff.config.record = :all

    with_ci("") do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        snap = create_snapshot_for(:a, :c)
        assert_nil SnapDiff::ScreenshotMatcher.new(snap.full_name).build_screenshot_assertion
      end
    end
  end

  # #capture never compares against a baseline, so `:all` has nothing to say
  # about it. Refusing there would be a failure invented out of a setting
  # that changes nothing on that path.
  test ":all does not refuse the compare-free #capture path under CI" do
    SnapDiff.config.record = :all
    name = "b_#{Time.now.nsec}"

    with_ci("true") do
      SnapDiff::ScreenshotMatcher.new(name).capture
    end

    assert_predicate SnapDiff::SnapManager.path_for(name).path, :exist?
  end

  # The refusal is about :all only -- a CI run on any other mode is the
  # normal case and must be untouched.
  test ":once and :none are unaffected by CI" do
    with_ci("true") do
      SnapDiff.config.record = :once

      capture_io do
        SnapDiff::Vcs.stub(:checkout_vcs, false) do
          assert_nil SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}").build_screenshot_assertion
        end
      end
    end
  end

  # --- the per-screenshot option ----------------------------------------

  test "a per-screenshot record: outranks the configured mode" do
    SnapDiff.config.record = :none

    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_nil SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}", record: :all).build_screenshot_assertion
    end
  end

  test "a per-screenshot record: :none raises where the configured :once would not" do
    SnapDiff.config.record = :once

    SnapDiff::Vcs.stub(:checkout_vcs, false) do
      assert_raises(SnapDiff::ExpectationNotMet) do
        SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}", record: :none).build_screenshot_assertion
      end
    end
  end

  # `record:` is a workflow mode, not a capture or comparison option. It has
  # to be carved out before the options hash reaches Comparison, or ADR-010's
  # unknown-key check would warn at every user who sets it.
  test "record: never reaches the capture or comparison options" do
    seen = []
    screenshoter = Class.new do
      define_method(:initialize) { |capture, comparison| seen << [capture, comparison] }

      def take_comparison_screenshot(snapshot)
        snapshot.path.dirname.mkpath
        FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), snapshot.path)
      end
    end

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      SnapDiff.config.stub(:screenshoter, screenshoter) do
        snap = create_snapshot_for(:a, :c)
        SnapDiff::ScreenshotMatcher.new(snap.full_name, record: :once).build_screenshot_assertion
      end
    end

    capture_options, comparison_options = seen.fetch(0)
    assert_not_includes capture_options, :record
    assert_not_includes comparison_options, :record
    assert_not_includes SnapDiff::Comparison::KNOWN_OPTIONS, :record,
      ":record is carved out upstream, so accepting it at Comparison would be a silent no-op (ADR-010)"
  end

  # --- a typo must not silently mean "not set" --------------------------

  test "an unknown mode raises at config time" do
    error = assert_raises(ArgumentError) { SnapDiff.config.record = :non }

    assert_match(/:non/, error.message)
    assert_match(/:once/, error.message)
  end

  test "an unknown per-screenshot mode raises" do
    assert_raises(ArgumentError) do
      SnapDiff::ScreenshotMatcher.new("c_#{Time.now.nsec}", record: "all")
    end
  end

  # --- THE USER'S CODE --------------------------------------------------
  #
  # Their config, their assertion, through the documented DSL -- not the
  # matcher internals every other example here pokes at. This is the shape
  # of the accept workflow as it is documented, and if it stops working the
  # feature is gone whatever the unit tests say.

  test "a user accepts an intentional change with SnapDiff.config.record = :all" do
    snap = nil

    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)

      SnapDiff.configure { |config| config.record = :all }

      # false is what every "nothing was compared" path already returns --
      # the same answer a screenshot with no baseline gives today.
      assert_equal false, assert_matches_screenshot(snap.full_name)
    end

    SnapDiff.session.verify

    assert_captured(:c, snap.path, "the accepted rendering is what the user is left to `git add`")
  end

  test "the same user assertion fails on the default mode" do
    SnapDiff::Vcs.stub(:checkout_vcs, true) do
      snap = create_snapshot_for(:a, :c)

      SnapDiff.configure { |config| config.record = :once }

      assert assert_matches_screenshot(snap.full_name)

      assert_raises(SnapDiff::ExpectationNotMet) { SnapDiff.session.verify }
    end
  end

  private

  # Compares by IMAGE, not by bytes: the screenshoter re-encodes what it
  # captures, so a byte match against the source fixture proves nothing
  # either way.
  def assert_captured(fixture, path, message)
    assert_predicate SnapDiff::Comparison.new(path, fixture_image_path_from(fixture)), :quick_equal?, message
  end

  def assert_not_captured(fixture, path, message)
    assert_not_predicate SnapDiff::Comparison.new(path, fixture_image_path_from(fixture)), :quick_equal?, message
  end

  # This class exercises record modes; `:all` deliberately refuses to run under
  # CI, so the whole class runs as a developer's laptop by default and the
  # CI-refusal cases opt IN via `with_ci`. Without this, every `:all` example
  # fails on CI for the very reason it is testing -- and passes locally, where
  # ENV["CI"] is unset. Local green was half the bar here.
  def setup
    super
    @original_ci = ENV.delete("CI")
  end

  def teardown
    ENV["CI"] = @original_ci
    super
  end

  def with_ci(value)
    original = ENV["CI"]
    ENV["CI"] = value
    yield
  ensure
    ENV["CI"] = original
  end
end
