# frozen_string_literal: true

require "test_helper"
require "snap_diff"

module SnapDiff
  # `status` is the one answer to "what became of this capture?". It is
  # derived on every call (a comparison can be assigned after the fact) and
  # must never be the thing that triggers the comparison.
  class ScreenshotAssertionStatusTest < ActiveSupport::TestCase
    include DSLStub

    test "#status is :passed when the comparison matches" do
      assert_equal :passed, build(compare: make_comparison(:a, :a).tap(&:processed)).status
    end

    test "#status is :changed when the comparison differs" do
      assert_equal :changed, build(compare: make_comparison(:a, :b).tap(&:processed)).status
    end

    test "#status is :new without a comparison" do
      assert_equal :new, build.status
    end

    test "#status is :new without a comparison under record: :all" do
      assert_equal :new, build(record_mode: :all).status
    end

    test "#status is :passed for a matching comparison under record: :all" do
      assert_equal :passed, build(compare: make_comparison(:a, :a).tap(&:processed), record_mode: :all).status
    end

    test "#status is :rerecorded for a differing comparison under record: :all" do
      assert_equal :rerecorded, build(compare: make_comparison(:a, :b).tap(&:processed), record_mode: :all).status
    end

    # A capture that vanished is not a difference anyone accepted: `:rerecorded`
    # would pass the test and tell the user to `git add` a path that no longer
    # exists, which commits the deletion of the tracked baseline.
    test "#status is :changed for a vanished capture, under record: :all too" do
      comparison = make_comparison(:a, :b)
      comparison.image_path.delete
      comparison.processed

      assert_equal :changed, build(compare: comparison, record_mode: :all).status
      assert_equal :changed, build(compare: comparison).status
    end

    test "#status reads :passed for an unprocessed comparison without processing it" do
      comparison = make_comparison(:a, :b)

      assert_equal :passed, build(compare: comparison).status
      assert_not comparison.processed?, "reading status must not force the comparison"
    end

    # #verdict is the one place that forces the comparison; #status stays a
    # pure read. Every caller that needs a judgment goes through it.
    test "#verdict judges an unprocessed comparison where #status would read :passed" do
      comparison = make_comparison(:a, :b)
      assertion = build(compare: comparison)

      assert_equal :changed, assertion.verdict
      assert_predicate comparison, :processed?
      assert_equal :new, build.verdict
      assert_equal :rerecorded, build(compare: make_comparison(:a, :b, destination: "two"), record_mode: :all).verdict
    end

    test "#status is not memoized across #compare=" do
      assertion = build

      assert_equal :new, assertion.status

      assertion.compare = make_comparison(:a, :b).tap(&:processed)

      assert_equal :changed, assertion.status
    end

    test "#path falls back to the comparison's image path" do
      comparison = make_comparison(:a, :a)

      assert_equal comparison.image_path, build(compare: comparison).path
      assert_equal Pathname("x.png"), build(path: Pathname("x.png")).path
    end

    test "AssertionRegistry#failed_assertions lists :changed assertions that were not already validated" do
      registry = AssertionRegistry.new
      changed = build(compare: make_comparison(:a, :b, destination: "one").tap(&:processed))
      raised = build(compare: make_comparison(:a, :b, destination: "two").tap(&:processed))
      passed = build(compare: make_comparison(:a, :a, destination: "three").tap(&:processed))
      [changed, raised, passed, build].each { |assertion| registry.add_assertion(assertion) }
      raised.caller = ["my_test.rb:1"]
      assert_raises(SnapDiff::ExpectationNotMet) { raised.validate! }

      assert_equal [changed], registry.failed_assertions
    end

    # Callers ask it for a verdict (the integration suite and the delayed
    # `verify` path), so it has to judge comparisons nobody has judged yet.
    # #status alone would read an unprocessed one as :passed.
    test "AssertionRegistry#failed_assertions judges comparisons that were not processed yet" do
      registry = AssertionRegistry.new
      unjudged = build(compare: make_comparison(:a, :b, destination: "one"))
      rerecorded = build(compare: make_comparison(:a, :b, destination: "two"), record_mode: :all)
      [unjudged, rerecorded].each { |assertion| registry.add_assertion(assertion) }

      assert_equal [unjudged], registry.failed_assertions
    end

    test "AssertionRegistry#record_new_screenshot registers a :new assertion and #add_assertion still ignores nil" do
      registry = AssertionRegistry.new
      registry.record_new_screenshot("shot")

      assert_nil registry.add_assertion(nil)
      assert_equal [["shot", :new]], registry.assertions.map { |a| [a.name, a.status] }
      assert_equal ["shot"], registry.new_screenshots
    end

    private

    def build(compare: nil, **args)
      ScreenshotAssertion.new("name", **args).tap { |assertion| assertion.compare = compare }
    end
  end
end
