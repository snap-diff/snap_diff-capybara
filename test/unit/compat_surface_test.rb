# frozen_string_literal: true

require "test_helper"
require "open3"
# .probe runs a require in a fresh process with only lib/ on the load path.
# Reused rather than copied so the two suites cannot drift apart.
require_relative "support_load_probe_test"

# THE 2.1 SAFETY NET, WRITTEN AS THE USER'S CODE.
#
# ADR-008 said "no demand" for the v1 names, the `driver` setting and
# `shift_distance_limit`. Research on 2026-08-24 falsified it against the live
# GitHub API (.ai/adr-008-amendment-demand-falsified.md):
#
#   - `CapybaraScreenshotDiff::DSL` / `::Minitest::Assertions` is the entry
#     point 4 of 6 discoverable real users already migrated TO. Zero are on
#     `SnapDiff::*`.
#   - 3 of 6 real configs set `driver` explicitly; two set it to `:vips` --
#     asking for the only backend that survives.
#   - `shift_distance_limit`'s one known user guards the writer with
#     `respond_to?`, so plain deletion is SILENT for them: no error, no
#     warning, tolerance quietly gone. That is the worst possible removal.
#
# So 2.1 keeps the vips-only simplification and changes the FAILURE MODE: the
# names users import survive as permanent aliases, and every seam that is
# really gone raises with a message naming the replacement.
#
# Every assertion below is written the way the affected user wrote it -- their
# `require`, their constant, their assignment -- deliberately NOT as an
# internal unit test of SnapDiff::Config. The whole bug being fixed is that
# the internal tests were green while the user-facing imports broke.
#
# This file is excluded WHOLE from canonical_suite_has_no_legacy_refs_test:
# its entire subject is the v1 alias surface, so a line allowlist for a file
# whose every line is the subject buys nothing. The gate still holds for the
# rest of test/unit and test/integration.
class CompatSurfaceTest < ActiveSupport::TestCase
  # --- ITEM 1: the names users actually import survive -----------------
  #
  # EAGER same-object aliases, not lazy `const_missing` shims. The
  # distinction is load-bearing and has already produced one false CHANGELOG
  # claim in this project: `const_defined?` and `defined?` never trigger
  # `const_missing`, so a lazy shim breaks every adopter that feature-detects
  # before including.

  test "CapybaraScreenshotDiff::DSL is the same object as SnapDiff::DSL" do
    assert_same SnapDiff::DSL, CapybaraScreenshotDiff::DSL
  end

  test "CapybaraScreenshotDiff::Minitest::Assertions is the same object as the canonical one" do
    assert_same SnapDiff::Minitest::Assertions, CapybaraScreenshotDiff::Minitest::Assertions
  end

  test "Capybara::Screenshot::Diff is the same object as SnapDiff" do
    assert_same SnapDiff, Capybara::Screenshot::Diff
  end

  # The eager-vs-lazy contract, asserted the way adopters check it.
  test "the alias constants answer const_defined? and defined? without being resolved first" do
    %w[
      CapybaraScreenshotDiff
      CapybaraScreenshotDiff::DSL
      CapybaraScreenshotDiff::Minitest::Assertions
      Capybara::Screenshot::Diff
    ].each do |name|
      assert Object.const_defined?(name),
        "#{name} is not const_defined? -- a lazy const_missing shim, not an eager alias"
    end

    assert defined?(CapybaraScreenshotDiff::DSL)
    assert defined?(Capybara::Screenshot::Diff)
  end

  # "call what they call": the alias has to carry the DSL methods, not just
  # resolve to a module object.
  test "the aliased DSL carries the assertion methods a user includes it for" do
    assert_includes CapybaraScreenshotDiff::DSL.instance_methods, :assert_matches_screenshot
    assert_includes CapybaraScreenshotDiff::DSL.instance_methods, :screenshot
    assert_includes CapybaraScreenshotDiff::Minitest::Assertions.instance_methods, :assert_matches_screenshot
  end

  # The require lines the six real configs actually have at the top of their
  # support files. A LoadError here is the first thing they would hit -- before
  # any constant above could help them.
  LEGACY_REQUIRES = {
    "capybara_screenshot_diff/minitest" => %w[CapybaraScreenshotDiff::DSL CapybaraScreenshotDiff::Minitest::Assertions],
    "capybara_screenshot_diff/rspec" => %w[CapybaraScreenshotDiff::DSL],
    "capybara_screenshot_diff/dsl" => %w[CapybaraScreenshotDiff::DSL],
    "capybara_screenshot_diff" => %w[CapybaraScreenshotDiff],
    "capybara/screenshot/diff" => %w[Capybara::Screenshot::Diff CapybaraScreenshotDiff::DSL]
  }.freeze

  test "every require line the real configs use still loads and defines what they name" do
    failures = LEGACY_REQUIRES.filter_map do |entry, constants|
      SupportLoadProbeTest.probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{constants.inspect}.reject { |c| Object.const_defined?(c) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      A require line real users have at the top of their support file no
      longer loads, or no longer defines the constant they name after it:

      #{failures.join("\n")}
    MSG
  end

  # --- ITEM 2: `driver` is accept-and-ignore, except chunky_png --------

  test "setting driver to vips is a silent no-op through the name real configs use" do
    assert_silent { Capybara::Screenshot::Diff.driver = :vips }
    assert_equal :vips, Capybara::Screenshot::Diff.driver
  end

  test "setting driver to auto is accepted and ignored" do
    assert_silent { SnapDiff.config.driver = :auto }
    assert_equal :vips, SnapDiff.config.driver
  end

  # bootstrap_form (1,643 stars) has exactly this line, and its CI installs no
  # libvips. This is the message that has to tell them what to do.
  test "setting driver to chunky_png raises and names libvips, ruby-vips and the upgrade doc" do
    error = assert_raises(ArgumentError) do
      Capybara::Screenshot::Diff.driver = ENV.fetch("SCREENSHOT_DRIVER", "chunky_png").to_sym
    end

    assert_match(/chunky_png/, error.message)
    assert_match(/libvips/, error.message)
    assert_match(/ruby-vips/, error.message)
    assert_match(%r{docs/UPGRADING\.md}, error.message)
  end

  test "the chunky_png rejection does not depend on the value being a symbol" do
    assert_raises(ArgumentError) { SnapDiff.config.driver = "chunky_png" }
  end

  # --- ITEM 3: shift_distance_limit raises instead of vanishing --------

  # potlift8 writes exactly this guard, which is why plain deletion is silent
  # for them: `respond_to?` goes false and the whole line evaporates.
  test "the shift_distance_limit writer still answers respond_to?" do
    assert Capybara::Screenshot::Diff.respond_to?(:shift_distance_limit=),
      "the respond_to?-guarded writer vanished -- removal is silent for its one known user"
    assert SnapDiff.config.respond_to?(:shift_distance_limit=)
  end

  test "setting shift_distance_limit raises and names what to use instead" do
    error = assert_raises(ArgumentError) do
      Capybara::Screenshot::Diff.shift_distance_limit = 1 if
        Capybara::Screenshot::Diff.respond_to?(:shift_distance_limit=)
    end

    assert_match(/shift_distance_limit/, error.message)
    assert_match(/tolerance/, error.message)
    assert_match(/color_distance_limit/, error.message)
    assert_match(%r{docs/UPGRADING\.md}, error.message)
  end

  test "setting shift_distance_limit on the config object raises too" do
    assert_raises(ArgumentError) { SnapDiff.config.shift_distance_limit = 1 }
  end

  # --- ITEM 3, THE CLASS: per-comparison options ----------------------
  #
  # The settings above are only half the surface a user can write. The other
  # half is the per-screenshot options hash, which Comparison froze and never
  # validated -- so `screenshot "home", shift_distance_limit: 5` was a SILENT
  # no-op for exactly the same reason the writer was. One guard at the funnel
  # every option hash passes through, not one per call site.

  test "a removed option in the per-comparison hash raises rather than being ignored" do
    images = TEST_IMAGES_DIR.join("a.png").to_s

    assert_raises(ArgumentError) { SnapDiff::Comparison.new(images, images, shift_distance_limit: 5) }
    assert_raises(ArgumentError) { SnapDiff::Comparison.new(images, images, driver: :chunky_png) }
  end

  test "a per-comparison driver option that names the surviving backend is ignored silently" do
    images = TEST_IMAGES_DIR.join("a.png").to_s

    assert_silent { SnapDiff::Comparison.new(images, images, driver: :vips) }
  end

  # The defaults every comparison carries must not trip the guard above --
  # a false positive here breaks every user at once.
  test "the default options a normal comparison carries trip no removed-option guard" do
    images = TEST_IMAGES_DIR.join("a.png").to_s

    assert_silent { SnapDiff::Comparison.new(images, images, SnapDiff.config.default_options) }
  end

  # --- ITEM 5: the dual-install guard's load-bearing assumption --------
  #
  # SnapDiff.assert_single_gem! reads Gem.loaded_specs. snap_diff_test.rb
  # proves the predicate fires on a two-gem hash and stays quiet on a one-gem
  # one -- but both hand it a hash, so neither proves the REAL source is
  # populated the way the guard assumes.
  #
  # Measured 2026-08-24 with two path-sourced gems shipping identical files:
  # both names appear in Gem.loaded_specs with neither ever required, and only
  # one appears when only one is in the Gemfile. The assertion below is that
  # experiment reduced to something this suite can keep running: `standard` is
  # in the bundle, is never required by the suite, and is in loaded_specs
  # anyway. Bundle membership, not `require`, is what populates it.
  test "Bundler populates Gem.loaded_specs from bundle membership, not from require" do
    skip "not running under Bundler" unless defined?(Bundler) && Gem.loaded_specs.key?("capybara-screenshot-diff")

    assert Gem.loaded_specs.key?("standard"),
      "a bundled gem is missing from Gem.loaded_specs -- assert_single_gem! cannot see a second gem either"
    assert_empty $LOADED_FEATURES.grep(%r{/standard/base\.rb\z}),
      "standard got required after all, so this proves nothing about un-required bundle members"

    # ...and the guard's own negative: the second gem name is NOT in this
    # bundle, so the real Gem.loaded_specs must not trip it.
    assert_not Gem.loaded_specs.key?("snap_diff-capybara")
    assert_nil SnapDiff.assert_single_gem!
  end

  # --- ITEM 1b: the settings those imports actually CALL ---------------
  #
  # The names users IMPORT and the names they CALL are different surfaces, and
  # aliasing only the first is worse than aliasing neither: the constant
  # resolves, the user believes they are fine, and the next line explodes. Four
  # of six known real configs write `Capybara::Screenshot::Diff.tolerance=` or
  # a sibling. Since `Capybara::Screenshot::Diff` IS `SnapDiff`, the config
  # surface either exists on both or on neither -- there is no partial version.

  test "a v1 setting written through the old namespace lands in the one storage" do
    Capybara::Screenshot::Diff.tolerance = 0.05

    assert_in_delta 0.05, SnapDiff.config.tolerance
  end

  test "a setting written canonically is visible through the old namespace" do
    SnapDiff.config.color_distance_limit = 15

    assert_equal 15, Capybara::Screenshot::Diff.color_distance_limit
  end

  test "the capture-side holder writes the same storage too" do
    Capybara::Screenshot.window_size = [1400, 1400]

    assert_equal [1400, 1400], SnapDiff.config.window_size
  end

  # The one name that is NOT identity-mapped. `Capybara::Screenshot.enabled`
  # and `Capybara::Screenshot::Diff.enabled` were always two independent
  # settings that happened to share a bare name under their own modules; a flat
  # Config cannot expose two attributes called `enabled`, so the capture-side
  # one became `screenshot_enabled`. Collapsing them would change `active?`.
  test "enabled stays two different settings, one per holder" do
    Capybara::Screenshot.enabled = false
    Capybara::Screenshot::Diff.enabled = true

    assert_equal false, SnapDiff.config.screenshot_enabled
    assert_equal true, SnapDiff.config.enabled
    assert_equal false, Capybara::Screenshot.enabled
    assert_equal true, Capybara::Screenshot::Diff.enabled
  end

  # `mattr_accessor` defined instance methods as well as singleton ones, and
  # `include Capybara::Screenshot::Diff` (bootstrap_form has that line) is how
  # they were reached. An include that silently adds nothing is the same class
  # of failure as a setter that silently does nothing.
  test "including the old namespace still brings the settings in as instance methods" do
    SnapDiff.config.tolerance = 0.02
    host = Class.new { include Capybara::Screenshot::Diff }.new

    assert_in_delta 0.02, host.tolerance

    host.tolerance = 0.04
    assert_in_delta 0.04, SnapDiff.config.tolerance
  end

  # THE DRIFT GUARD. The accessors are generated from Config::SETTINGS, so a
  # new setting cannot be forgotten -- unless the generation itself is removed
  # or narrowed. This is what notices that.
  test "every Config setting is reachable through both v1 holders, on the module and on instances" do
    holders = [Capybara::Screenshot, Capybara::Screenshot::Diff]

    missing = SnapDiff::Config::SETTINGS.flat_map do |attr|
      holders.flat_map do |holder|
        [
          ["#{holder}.#{attr}", holder.respond_to?(attr)],
          ["#{holder}.#{attr}=", holder.respond_to?(:"#{attr}=")],
          ["#{holder}##{attr}", holder.method_defined?(attr)],
          ["#{holder}##{attr}=", holder.method_defined?(:"#{attr}=")]
        ].reject { |_name, present| present }.map(&:first)
      end
    end

    assert_empty missing, <<~MSG
      A setting exists on SnapDiff::Config but is unreachable through the v1
      holders. Real configs write these names; a missing one is a NoMethodError
      on line 1 of someone's test helper:

      #{missing.join("\n")}
    MSG
  end

  # The v1 two-block-arg form. Before the aliases this was a `NameError` --
  # loud. With `Capybara::Screenshot::Diff = SnapDiff` it would otherwise have
  # become a one-arg yield, handing the user `nil` for `diff` and a
  # NoMethodError three lines later. Both holders collapsed into one object, so
  # it yields that object twice and the old shape keeps working.
  test "the v1 two-holder configure block still works" do
    Capybara::Screenshot::Diff.configure do |screenshot, diff|
      screenshot.window_size = [800, 600]
      diff.tolerance = 0.003
    end

    assert_equal [800, 600], SnapDiff.config.window_size
    assert_in_delta 0.003, SnapDiff.config.tolerance
  end

  test "the canonical one-argument configure block is unaffected" do
    SnapDiff.configure { |config| config.tolerance = 0.007 }

    assert_in_delta 0.007, SnapDiff.config.tolerance
  end

  # --- ITEM 2b: the v1 error name in a rescue clause -------------------
  #
  # The worst variety of latent NameError: it fires only when an exception is
  # already in flight, converting someone's real failure into a confusing one
  # at the moment they can least afford it.
  test "rescuing by the v1 error name catches what the gem raises" do
    assert_same SnapDiff::Error, CapybaraScreenshotDiff::CapybaraScreenshotDiffError
    assert Object.const_defined?("CapybaraScreenshotDiff::CapybaraScreenshotDiffError")

    caught = begin
      raise SnapDiff::ExpectationNotMet, "boom"
    rescue CapybaraScreenshotDiff::CapybaraScreenshotDiffError => e
      e
    end

    assert_equal "boom", caught.message
  end

  # Discovered, not listed: a future error class added under SnapDiff is
  # reachable under the v1 namespace automatically (same module), and this says
  # so out loud rather than leaving it to be assumed.
  test "every error class the gem raises is reachable under the v1 namespace" do
    unreachable = SnapDiff.constants.filter_map { |name|
      value = SnapDiff.const_get(name)
      next unless value.is_a?(Class) && value <= SnapDiff::Error

      "CapybaraScreenshotDiff::#{name}" unless CapybaraScreenshotDiff.const_defined?(name)
    }

    assert_empty unreachable, "error class(es) not reachable under the v1 namespace: #{unreachable.join(", ")}"
  end

  # --- The six real configs, replayed verbatim -------------------------
  #
  # Not a unit test of anything: these are the actual lines from the
  # discoverable third-party setups, and the only claim is that a 2.1 process
  # survives running them.
  test "the discoverable real-world configs load without raising" do
    # jaynetics/activeadmin_assets, spec/support/capybara_setup.rb
    Capybara::Screenshot::Diff.driver = :vips
    Capybara::Screenshot::Diff.tolerance = 0.05
    Capybara::Screenshot::Diff.fail_if_new = !ENV["CI"].nil?

    # showca-se/showcase, test/support/system/setup_capybara_screenshot_diff.rb
    Capybara::Screenshot::Diff.driver = :vips
    Capybara::Screenshot.screenshot_format = :webp
    Capybara::Screenshot::Diff.color_distance_limit = 15

    assert_equal :webp, SnapDiff.config.screenshot_format
    assert_equal 15, SnapDiff.config.color_distance_limit
  end
end
