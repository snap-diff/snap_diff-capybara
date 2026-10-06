# frozen_string_literal: true

require "test_helper"

class ContributionsTest < Minitest::Test
  Provider = Struct.new(:note) do
    # Return the configured annotation for any screenshot name.
    def annotate(name) = note
  end

  # Save the existing providers and clear registry annotations for an isolated test.
  def setup
    # Snapshot the shared registry and restore it afterwards -- other
    # tests (and ai.rb's load-time self-registration) rely on providers
    # registered before this file runs.
    @saved_providers = SnapDiff::Contributions.instance_variable_get(:@providers).dup
    SnapDiff::Contributions.instance_variable_get(:@providers).clear
    SnapDiff::AI.clear_results! if defined?(SnapDiff::AI)
  end

  # Clear failure suppression and restore the providers saved before the test.
  def teardown
    SnapDiff::Contributions.register_suppression(nil)
    SnapDiff::Contributions.instance_variable_set(:@providers, @saved_providers)
  end

  # Verify that an empty registry produces no annotations.
  def test_annotations_empty_without_providers
    assert_empty SnapDiff::Contributions.annotations_for("never-recorded-name")
  end

  # Verify that absent annotations are skipped without changing provider order.
  def test_annotations_skip_nil_and_keep_order
    first = Provider.new({source: "first", text: "one"})
    nothing = Provider.new(nil)
    second = Provider.new({source: "second", text: "two"})
    [first, nothing, second].each { |p| SnapDiff::Contributions.register(p) }

    assert_equal %w[first second], SnapDiff::Contributions.annotations_for("x").map { |a| a[:source] }
  end

  # Verify that registering one provider twice yields only one annotation.
  def test_registering_the_same_provider_twice_is_a_no_op
    provider = Provider.new({source: "ai", text: "t"})
    2.times { SnapDiff::Contributions.register(provider) }

    assert_equal 1, SnapDiff::Contributions.annotations_for("x").size
  end

  # Verify that distinct providers contribute even when their values compare equal.
  def test_distinct_providers_that_compare_equal_both_contribute
    # Structs with equal fields are == but NOT the same provider.
    2.times { SnapDiff::Contributions.register(Provider.new({source: "ai", text: "t"})) }

    assert_equal 2, SnapDiff::Contributions.annotations_for("x").size
  end

  # Verify that an unset suppression slot neither advertises a gate nor waives failures.
  def test_no_suppressor_by_default
    refute SnapDiff::Contributions.any_suppressor?
    assert_nil SnapDiff::Contributions.suppression_for("x", Object.new)
  end

  # Verify that the latest suppressor replaces an earlier gate that would waive the failure.
  def test_suppression_single_slot_replaces
    waive = ->(_name, _diff) { {source: "ai", text: "FLAKY"} }
    waiving = Object.new
    waiving.define_singleton_method(:suppress) { |name, diff| waive.call(name, diff) }
    standing = Object.new
    standing.define_singleton_method(:suppress) { |_name, _diff| nil }

    SnapDiff::Contributions.register_suppression(waiving)
    SnapDiff::Contributions.register_suppression(standing)

    # Last registration wins: the earlier gate must not keep waiving.
    assert_nil SnapDiff::Contributions.suppression_for("x", Object.new)
  end

  # Verify that a registered suppressor returns its source and explanation unchanged.
  def test_suppression_returns_the_waiver
    waiving = Object.new
    waiving.define_singleton_method(:suppress) { |_name, _diff| {source: "ai", text: "FLAKY (clip)"} }
    SnapDiff::Contributions.register_suppression(waiving)

    assert SnapDiff::Contributions.any_suppressor?
    assert_equal({source: "ai", text: "FLAKY (clip)"}, SnapDiff::Contributions.suppression_for("x", Object.new))
  end
end
