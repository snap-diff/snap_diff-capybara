# frozen_string_literal: true

require "test_helper"

class ContributionsTest < Minitest::Test
  Provider = Struct.new(:note) do
    def annotate(name) = note
  end

  def setup
    # Other tests may have loaded AI and filled its store; annotations
    # must start from a known-empty state regardless of test order.
    SnapDiff::AI.clear_results! if defined?(SnapDiff::AI)
  end

  def teardown
    SnapDiff::Contributions.register_suppression(nil)
    SnapDiff::Contributions.instance_variable_get(:@providers).clear
    # ai.rb self-registers on load; other tests rely on that, so put it
    # back if the AI module is around.
    if defined?(SnapDiff::AI)
      SnapDiff::Contributions.register(SnapDiff::AI)
    end
  end

  def test_annotations_empty_without_providers
    assert_empty SnapDiff::Contributions.annotations_for("never-recorded-name")
  end

  def test_annotations_skip_nil_and_keep_order
    first = Provider.new({source: "first", text: "one"})
    nothing = Provider.new(nil)
    second = Provider.new({source: "second", text: "two"})
    [first, nothing, second].each { |p| SnapDiff::Contributions.register(p) }

    assert_equal %w[first second], SnapDiff::Contributions.annotations_for("x").map { |a| a[:source] }
  end

  def test_registering_the_same_provider_twice_is_a_no_op
    provider = Provider.new({source: "ai", text: "t"})
    2.times { SnapDiff::Contributions.register(provider) }

    assert_equal 1, SnapDiff::Contributions.annotations_for("x").size
  end

  def test_no_suppressor_by_default
    refute SnapDiff::Contributions.any_suppressor?
    assert_nil SnapDiff::Contributions.suppression_for("x", Object.new)
  end

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

  def test_suppression_returns_the_waiver
    waiving = Object.new
    waiving.define_singleton_method(:suppress) { |_name, _diff| {source: "ai", text: "FLAKY (clip)"} }
    SnapDiff::Contributions.register_suppression(waiving)

    assert SnapDiff::Contributions.any_suppressor?
    assert_equal({source: "ai", text: "FLAKY (clip)"}, SnapDiff::Contributions.suppression_for("x", Object.new))
  end
end
