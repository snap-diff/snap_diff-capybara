# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff"

module CapybaraScreenshotDiff
  # Guard #5 from the v2 core-redesign acceptance contract.
  #
  # Extends the single thread-isolation test (pending_screenshots_message) to
  # the whole registry surface: add_assertion / verify / reset racing across
  # threads must never leak assertions between threads. This is the regression
  # net for parallel test runners and for D7's thread-local store fix.
  class RegistryConcurrencyTest < ActiveSupport::TestCase
    PassingCompare = Struct.new(:name) do
      def different? = false

      def base_image_path = Pathname.new("/nonexistent/#{name}.base.png")
    end

    def build_assertion(name)
      assertion = SnapDiff::ScreenshotAssertion.new(name)
      assertion.caller = ["#{name}:1"]
      assertion.compare = PassingCompare.new(name)
      assertion
    end

    # ADR-008 step 6: SnapDiff.session is the canonical accessor and
    # CapybaraScreenshotDiff.registry a forwarder over it -- they must hand
    # back the *same* object, not two registries that happen to look alike.
    test "SnapDiff.session and CapybaraScreenshotDiff.registry are the same object" do
      assert_same SnapDiff.session, CapybaraScreenshotDiff.registry

      SnapDiff.session.record_new_screenshot("shared_object_probe")
      assert_equal ["shared_object_probe"], CapybaraScreenshotDiff.new_screenshots
    ensure
      SnapDiff.session.reset
    end

    test "each thread gets its own registry instance" do
      here = CapybaraScreenshotDiff.registry
      there = Thread.new { CapybaraScreenshotDiff.registry }.value

      assert_not_same here, there
    end

    test "add_assertion, verify and reset in concurrent threads never leak across threads" do
      threads = 2.times.map do |i|
        Thread.new do
          names = 25.times.map { |j| "thread_#{i}_shot_#{j}" }
          observed = []

          names.each do |name|
            CapybaraScreenshotDiff.add_assertion(build_assertion(name))
            CapybaraScreenshotDiff.record_new_screenshot(name)
            observed << CapybaraScreenshotDiff.assertions.map(&:name)
          end

          CapybaraScreenshotDiff.verify # all compares pass -> must not raise

          final_names = CapybaraScreenshotDiff.assertions.map(&:name)
          new_screenshots = CapybaraScreenshotDiff.new_screenshots.dup

          CapybaraScreenshotDiff.reset
          after_reset = CapybaraScreenshotDiff.assertions.size + CapybaraScreenshotDiff.new_screenshots.size

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
      assert_not_predicate CapybaraScreenshotDiff.registry, :assertions_present?
      assert_empty CapybaraScreenshotDiff.new_screenshots
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
        CapybaraScreenshotDiff.add_assertion(assertion)

        raised = assert_raises(CapybaraScreenshotDiff::ExpectationNotMet) { CapybaraScreenshotDiff.verify }
        CapybaraScreenshotDiff.registry.reset
        raised
      end

      passing_thread = Thread.new do
        CapybaraScreenshotDiff.add_assertion(build_assertion("passing_shot"))
        CapybaraScreenshotDiff.verify
        CapybaraScreenshotDiff.registry.reset
        :passed
      end

      assert_match(/failing_shot/, failing_thread.value.message)
      assert_equal :passed, passing_thread.value
    end
  end
end
