# frozen_string_literal: true

require "snap_diff/config"

# THE PERMANENT COMPATIBILITY SURFACE (ADR-008 amendment, 2026-08-24).
#
# 2.1 stays vips-only -- the driver abstraction, chunky_png and the v1
# implementation trees are gone and are not coming back. What lives here is
# only the FAILURE MODE, and it exists because "no demand" turned out to be
# false when it was finally measured against the live GitHub API:
#
#   - `CapybaraScreenshotDiff::DSL` / `::Minitest::Assertions` is the entry
#     point 4 of 6 discoverable real users had already migrated TO. Zero were
#     on `SnapDiff::*`. From the outside those names never read as "legacy";
#     until 2.0 they WERE the current API.
#   - 3 of 6 real configs set `driver` explicitly, two of them to `:vips` --
#     asking for the only backend that survives.
#   - `shift_distance_limit`'s one known user guards the writer with
#     `respond_to?`. Deleting the writer is SILENT for them: no error, no
#     warning, their anti-aliasing tolerance quietly gone and a suite that
#     starts failing for reasons no upgrade note can be traced to.
#
# So: the names users import survive as aliases, and every seam that really
# is gone raises with a message naming the replacement. Nothing here restores
# behaviour -- `driver` selects nothing and `shift_distance_limit` does
# nothing, they just stop being able to lie about it.
#
# EAGER same-object aliases, never `const_missing` shims. `const_defined?`
# and `defined?` do not trigger `const_missing`, so a lazy shim silently
# breaks every adopter that feature-detects before including -- a distinction
# that has already produced one false claim in this project's CHANGELOG.
#
# This is the one file under lib/ that core_tree_has_no_legacy_deps_test
# exempts. It is the compatibility surface; naming the old names is its job.
module SnapDiff
  # Named constants rather than inline strings: these messages are what the
  # affected users see, and compat_surface_test asserts on their content.
  CHUNKY_PNG_REMOVED =
    "`driver = :chunky_png` is removed in 2.1: libvips is the only backend. Install system " \
    "libvips (`apt-get install libvips-dev`, `brew install vips`) and the `ruby-vips` gem, then " \
    "drop the `driver` setting -- it is accepted and ignored for every other value. " \
    "See docs/UPGRADING.md."

  SHIFT_DISTANCE_LIMIT_REMOVED =
    "`shift_distance_limit` is removed in 2.1: only the chunky_png driver ever implemented it, " \
    "and that driver is gone. libvips has no shift-distance comparison -- drop the setting and " \
    "tune `tolerance` / `color_distance_limit` instead. See docs/UPGRADING.md."

  class Config
    # Accept-and-ignore. The two real configs that set this set it to `:vips`,
    # i.e. they are already asking for what they will get, so silence is the
    # honest answer for them; `:chunky_png` is the one value the gem can no
    # longer honour, so it is the one value that raises.
    def driver=(value)
      raise ArgumentError, CHUNKY_PNG_REMOVED if value.to_s == "chunky_png"
    end

    # Always :vips, whatever was assigned -- storing the assignment would let
    # a config keep claiming a backend choice that does not exist.
    def driver
      :vips
    end

    # A raising stub, not a deletion. The writer is what the one known user
    # `respond_to?`-guards, so it has to still BE there in order to say no.
    # nil is let through: it is what "never set" looks like when a config is
    # copied around, and raising on it would break people who set nothing.
    def shift_distance_limit=(value)
      raise ArgumentError, SHIFT_DISTANCE_LIMIT_REMOVED unless value.nil?
    end
  end

  class << self
    # The v1 namespaces are aliases of THIS module (below), so defining the
    # removed setters here is what puts them back on
    # `Capybara::Screenshot::Diff.driver=` -- the spelling every real config
    # actually uses.
    def driver
      config.driver
    end

    def driver=(value)
      config.driver = value
    end

    def shift_distance_limit=(value)
      config.shift_distance_limit = value
    end

    # @api private
    #
    # The other half of the surface a user can write: the per-screenshot
    # options hash. It was frozen and never validated, so
    # `screenshot "home", shift_distance_limit: 5` was a silent no-op for
    # exactly the same reason the writer was. One guard at the funnel every
    # options hash passes through (Comparison#initialize), not one per call
    # site -- and it reuses the setters above, so there is one message and one
    # rule per removed name.
    def reject_removed_options!(options)
      self.driver = options[:driver] if options.key?(:driver)
      self.shift_distance_limit = options[:shift_distance_limit] if options.key?(:shift_distance_limit)
    end
  end

  # The v1 error name, kept for `rescue` clauses. Worth its own line: a
  # NameError inside a rescue fires only when an exception is already in
  # flight, so it converts someone's real failure into a confusing one at the
  # moment they can least afford it. Every other v1 error name
  # (ExpectationNotMet, UnstableImage, WindowSizeMismatchError) is spelled the
  # same under SnapDiff and comes along with the module alias.
  CapybaraScreenshotDiffError = Error

  # @api private
  #
  # Regenerates the v1 `mattr_accessor` surface as thin delegators onto the one
  # storage in {SnapDiff.config}.
  #
  # GENERATED FROM Config::SETTINGS, deliberately: a hand-written table of 27
  # rows is a table that drifts the first time someone adds a setting, and the
  # failure mode of that drift is a NoMethodError on line 1 of a user's test
  # helper. compat_surface_test walks SETTINGS and fails if any name is
  # unreachable.
  #
  # Both holders get the full set rather than the historical split. The split
  # would need exactly the hand-maintained table this avoids, and widening a
  # holder cannot break anyone: it only accepts a spelling that used to raise.
  #
  # No deprecation warning: 2.1 deleted the channel that emitted them
  # (snap_diff/removal.rb, snap_diff/deprecation.rb) and one warning is not
  # worth resurrecting a subsystem for. These are plain delegators.
  module Compat
    # `enabled` is the one name that is not identity-mapped. The two v1 holders
    # each carried an independent `enabled` (see Config#active?, which reads
    # both); a flat Config cannot expose two attributes of that name, so the
    # capture-side one became `screenshot_enabled`. Collapsing them here would
    # change `active?`, so each holder says which attribute its `enabled` means.
    def self.install(namespace, enabled_maps_to:)
      mapping = Config::SETTINGS.to_h { |attr| [attr, attr] }
      mapping[:enabled] = enabled_maps_to

      mapping.each do |name, attr|
        # mattr_accessor defined BOTH singleton and instance accessors -- the
        # instance ones are what `include Capybara::Screenshot::Diff` picks up,
        # and an include that silently adds nothing is the same class of bug as
        # a setter that silently does nothing.
        [namespace, namespace.singleton_class].each do |target|
          target.define_method(name) { SnapDiff.config.public_send(attr) }
          target.define_method(:"#{name}=") { |value| SnapDiff.config.public_send(:"#{attr}=", value) }
        end
      end
    end
  end
end

# `CapybaraScreenshotDiff::DSL` and `::Minitest::Assertions` come along for
# free and stay same-object, because the module IS SnapDiff.
CapybaraScreenshotDiff = SnapDiff

module Capybara
  module Screenshot
    Diff = SnapDiff
  end
end

SnapDiff::Compat.install(Capybara::Screenshot, enabled_maps_to: :screenshot_enabled)
SnapDiff::Compat.install(Capybara::Screenshot::Diff, enabled_maps_to: :enabled)
