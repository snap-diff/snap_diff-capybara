# frozen_string_literal: true

require "test_helper"
require "open3"

# THE 2.1 REMOVALS, ANNOUNCED IN 2.0.
#
# 2.0 is the transitional release: the contract is published before it is
# enforced, so everything 2.1 deletes has to warn HERE, naming 2.1, while it
# still works. The legacy-namespace half of that promise is covered by
# test/legacy/; this file covers the driver half, which 2.1 removes whole:
# the chunky_png driver, `shift_distance_limit` (chunky-only, it dies with
# it), and the driver abstraction itself (`SnapDiff::Driver`,
# `SnapDiff::Drivers.loaded` / `.available`, `driver: :auto`) -- libvips
# becomes the only backend.
#
# Every example runs in a SUBPROCESS. "Once per process" is the contract, and
# this suite is a single long-lived process that selects chunky_png in
# hundreds of tests (test_helper suppresses these warnings for exactly that
# reason) -- an in-process assertion could measure neither.
class RemovedIn21DeprecationTest < ActiveSupport::TestCase
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  IMAGE_A = File.join(PROJECT_ROOT, "test/fixtures/images/a.png")
  IMAGE_B = File.join(PROJECT_ROOT, "test/fixtures/images/b.png")

  # Blocks `require "vips"` so detection reports chunky_png only -- the
  # `driver: :auto` fallback a user without libvips is silently on today.
  # (Same technique as drivers_test's unavailable-leaf probe.)
  NO_VIPS = <<~RUBY
    module Kernel
      alias_method :__real_require, :require
      def require(name)
        raise LoadError, "cannot load such file -- vips" if name == "vips"
        __real_require(name)
      end
    end
  RUBY

  # --- the chunky_png driver ------------------------------------------

  test "selecting chunky_png per comparison warns once, naming 2.1" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { #{compare(driver: :chunky_png)} }
    RUBY

    # Counts the chunky lines, not every line: picking a driver AT ALL is
    # its own removal (see the driver-setting examples below), so this
    # caller legitimately hears two different things.
    chunky = lines.grep(/chunky_png driver/)
    assert_equal 1, chunky.size, lines.join
    assert_match(/REMOVED in 2\.1/, chunky.first)
    assert_match(/vips/, chunky.first)
  end

  test "selecting chunky_png through SnapDiff.config.driver warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      SnapDiff.config.driver = :chunky_png
      3.times { #{compare} }
    RUBY

    assert_equal 1, lines.grep(/chunky_png driver/).size, lines.join
  end

  # THE CASE THAT MATTERS MOST: these users never asked for chunky_png and
  # have no idea they are on it, so the warning has to say why they are.
  test "the :auto fallback to chunky_png warns and says libvips is missing" do
    lines = probe(<<~RUBY)
      #{NO_VIPS}
      require "snap_diff"
      3.times { #{compare} }
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/auto/, lines.first)
    assert_match(/libvips/, lines.first)
    assert_match(/REMOVED in 2\.1/, lines.first)
  end

  # --- shift_distance_limit (chunky-only, dies with it) ----------------

  test "setting shift_distance_limit on the config warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { SnapDiff.config.shift_distance_limit = 5 }
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/shift_distance_limit/, lines.first)
    assert_match(/REMOVED in 2\.1/, lines.first)
  end

  # Counts the shift lines rather than every line: the driver is left to
  # `:auto` so this runs on a box with or without libvips, and a box without
  # it legitimately gets the chunky_png fallback warning as well.
  test "passing shift_distance_limit per comparison warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { #{compare(shift_distance_limit: 5)} }
    RUBY

    shift = lines.grep(/shift_distance_limit/)
    assert_equal 1, shift.size, lines.join
    assert_match(/REMOVED in 2\.1/, shift.first)
  end

  # --- the driver abstraction ------------------------------------------

  test "reading the custom-driver registry warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff/drivers"
      3.times { SnapDiff::Drivers.loaded[:mine] = Class.new }
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/SnapDiff::Drivers\.loaded/, lines.first)
    assert_match(/REMOVED in 2\.1/, lines.first)
  end

  test "reading the detected-driver list warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff/drivers"
      3.times { SnapDiff::Drivers.available }
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/SnapDiff::Drivers\.available/, lines.first)
  end

  test "a custom driver including the Driver mixin warns once" do
    lines = probe(<<~RUBY)
      require "snap_diff/driver"
      class MyDriver
        include SnapDiff::Driver
      end
      class MyOtherDriver
        include SnapDiff::Driver
      end
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/include SnapDiff::Driver/, lines.first)
    assert_match(/REMOVED in 2\.1/, lines.first)
  end

  # --- the `driver` setting and the `driver:` option -------------------
  #
  # The abstraction goes, so the knob that picks between implementations
  # goes with it -- whichever value it is set to. `driver: :vips` is the
  # case that needs saying out loud: it warns about nothing today (it is
  # the surviving backend) and it is exactly the line that stops existing
  # in 2.1.

  test "setting the driver on the config warns once, whatever the value" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { SnapDiff.config.driver = :vips }
    RUBY

    assert_equal 1, lines.size, lines.join
    assert_match(/`driver`/, lines.first)
    assert_match(/REMOVED in 2\.1/, lines.first)
  end

  test "passing driver: per comparison warns once, whatever the value" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times { #{compare(driver: :vips)} }
    RUBY

    driver = lines.grep(/`driver`/)
    assert_equal 1, driver.size, lines.join
    assert_match(/REMOVED in 2\.1/, driver.first)
  end

  # The trap that made shift_distance_limit hard: config.default_options
  # carries :driver on EVERY comparison. Presence in the merged hash is not
  # evidence that the user asked for it.
  test "the driver: key config always merges in does not warn by itself" do
    out = probe_stderr(<<~RUBY)
      require "snap_diff"
      3.times { #{compare} }
    RUBY

    assert_empty out.lines.grep(/`driver`/), "config's own default must not warn at the user"
  end

  # --- what must stay silent -------------------------------------------

  # The mutation that matters for everyone who is NOT affected: a plain vips
  # setup, comparing images, must not gain a single line of stderr -- and the
  # gem's own drivers include the mixin themselves, so an unscoped `included`
  # hook would fire here.
  #
  # No `config.driver = :vips` here any more: that line is itself removed in
  # 2.1 and now warns (see the driver-setting examples above). Leaving vips
  # to :auto is what an unaffected setup looks like on this box.
  test "a plain vips setup with no chunky or shift usage stays silent" do
    skip "libvips not available on this box" unless SnapDiff::Drivers::AVAILABLE_DRIVERS.include?(:vips)

    out = probe_stderr(<<~RUBY)
      require "snap_diff"
      3.times { #{compare} }
      SnapDiff::Drivers::VipsDriver
    RUBY

    assert_equal "", out, "a vips-only setup must not warn"
  end

  # The other half of "the gem must not warn at itself": on a box with NO
  # libvips, every internal load path runs through chunky_png. Loading the
  # gem still has to be silent -- the warning belongs to the first
  # comparison the user asks for, not to `require`.
  test "loading the gem selects nothing and stays silent even without libvips" do
    out = probe_stderr(<<~RUBY)
      #{NO_VIPS}
      require "snap_diff"
      SnapDiff.config
    RUBY

    assert_equal "", out, "requiring the gem must not select a driver"
  end

  test "every warning fires exactly once per process, however many surfaces are touched" do
    lines = probe(<<~RUBY)
      require "snap_diff"
      3.times do
        SnapDiff.config.shift_distance_limit = 5
        SnapDiff.config.driver = :chunky_png
        #{compare}
        SnapDiff::Drivers.loaded
        SnapDiff::Drivers.available
        Class.new { include SnapDiff::Driver }
      end
    RUBY

    assert_equal 6, lines.size, lines.join
    assert_equal 6, lines.uniq.size, "duplicate warning text: #{lines.join}"
  end

  # --- silencing --------------------------------------------------------

  test "silenced by the SnapDiff.silence_deprecations accessor" do
    out = probe_stderr(<<~RUBY)
      require "snap_diff"
      SnapDiff.silence_deprecations = true
      SnapDiff.config.shift_distance_limit = 5
      #{compare(driver: :chunky_png)}
      SnapDiff::Drivers.loaded
      SnapDiff::Drivers.available
      Class.new { include SnapDiff::Driver }
    RUBY

    assert_equal "", out
  end

  test "silenced by SNAP_DIFF_SILENCE_DEPRECATIONS" do
    out = probe_stderr(<<~RUBY, "SNAP_DIFF_SILENCE_DEPRECATIONS" => "1")
      require "snap_diff"
      SnapDiff.config.shift_distance_limit = 5
      #{compare(driver: :chunky_png)}
      SnapDiff::Drivers.loaded
      SnapDiff::Drivers.available
      Class.new { include SnapDiff::Driver }
    RUBY

    assert_equal "", out
  end

  private

  # `SnapDiff.compare(base, new, **options)` against two real fixtures --
  # the documented entry point, so the probes exercise driver selection the
  # way an adopter reaches it rather than by poking at internals.
  def compare(**options)
    args = [IMAGE_A.inspect, IMAGE_B.inspect]
    options.each { |key, value| args << "#{key}: #{value.inspect}" }
    "SnapDiff.compare(#{args.join(", ")})"
  end

  def probe(script, env = {})
    probe_stderr(script, env).lines.reject { |line| line.strip.empty? }
  end

  # Runs +script+ in a fresh process with only lib/ on the load path and
  # returns this gem's warnings from its stderr (other gems' warnings are
  # none of this test's business).
  def probe_stderr(script, env = {})
    _out, err, status = Open3.capture3(
      env, RbConfig.ruby, "-Ilib", "-e", script, chdir: PROJECT_ROOT
    )
    assert_predicate status, :success?, err
    err.lines.grep(/\[snap_diff/).join
  end
end
