# frozen_string_literal: true

require "test_helper"
require "snap_diff"

# Guard #5 from the v2 core-redesign acceptance contract.
#
# Extends the single thread-isolation test (pending_screenshots_message) to
# the whole registry surface: add_assertion / verify / reset racing across
# threads must never leak assertions between threads. This is the regression
# net for parallel test runners and for D7's thread-local store fix.
class RegistryConcurrencyTest < ActiveSupport::TestCase
  PassingCompare = Struct.new(:name) do
    def different? = false

    # A processed comparison that matched: SnapDiff::Reporting.count reads
    # this to tally the run.
    def difference = TestDoubles::TestDifference.new(false)

    def base_image_path = Pathname.new("/nonexistent/#{name}.base.png")
  end

  def build_assertion(name)
    assertion = SnapDiff::ScreenshotAssertion.new(name)
    assertion.caller = ["#{name}:1"]
    assertion.compare = PassingCompare.new(name)
    assertion
  end

  # Memoized per fiber: repeated reads hand back the one registry the test
  # is accumulating into, not a fresh empty one.
  # (The identity of the v1 CapybaraScreenshotDiff.registry forwarder with
  # this accessor is pinned in test/legacy/legacy_forwarders_test.rb.)
  test "SnapDiff.session returns the same registry within a fiber" do
    assert_same SnapDiff.session, SnapDiff.session

    SnapDiff.session.record_new_screenshot("shared_object_probe")
    assert_equal ["shared_object_probe"], SnapDiff.session.new_screenshots
  ensure
    SnapDiff.session.reset
  end

  test "each thread gets its own registry instance" do
    here = SnapDiff.session
    there = Thread.new { SnapDiff.session }.value

    assert_not_same here, there
  end

  test "add_assertion, verify and reset in concurrent threads never leak across threads" do
    threads = 2.times.map do |i|
      Thread.new do
        names = 25.times.map { |j| "thread_#{i}_shot_#{j}" }
        observed = []

        names.each do |name|
          SnapDiff.session.add_assertion(build_assertion(name))
          SnapDiff.session.record_new_screenshot(name)
          observed << SnapDiff.session.assertions.map(&:name)
        end

        SnapDiff.session.verify # all compares pass -> must not raise

        final_names = SnapDiff.session.assertions.map(&:name)
        new_screenshots = SnapDiff.session.new_screenshots.dup

        SnapDiff.reset
        after_reset = SnapDiff.session.assertions.size + SnapDiff.session.new_screenshots.size

        {names: names, observed: observed, final_names: final_names,
         new_screenshots: new_screenshots, after_reset: after_reset}
      end
    end

    threads.map(&:value).each do |result|
      # At every point each thread saw only its own assertions, in order.
      result[:observed].each_with_index do |snapshot_of_names, index|
        assert_equal result[:names].first(index + 1), snapshot_of_names
      end
      assert_equal result[:names], result[:final_names]
      assert_equal result[:names], result[:new_screenshots]
      assert_equal 0, result[:after_reset], "reset must clear only the calling thread's registry"
    end

    # The main thread's registry stayed untouched by the worker threads.
    assert_not_predicate SnapDiff.session, :assertions_present?
    assert_empty SnapDiff.session.new_screenshots
  end

  test "a failing assertion in one thread does not fail verify in another" do
    failing_compare = Struct.new(:name) {
      def different? = true

      def error_message = "boom"
    }

    failing_thread = Thread.new do
      assertion = SnapDiff::ScreenshotAssertion.new("failing_shot")
      assertion.caller = ["failing_shot:1"]
      assertion.compare = failing_compare.new("failing_shot")
      SnapDiff.session.add_assertion(assertion)

      raised = assert_raises(SnapDiff::ExpectationNotMet) { SnapDiff.session.verify }
      SnapDiff.session.reset
      raised
    end

    passing_thread = Thread.new do
      SnapDiff.session.add_assertion(build_assertion("passing_shot"))
      SnapDiff.session.verify
      SnapDiff.session.reset
      :passed
    end

    assert_match(/failing_shot/, failing_thread.value.message)
    assert_equal :passed, passing_thread.value
  end
end
