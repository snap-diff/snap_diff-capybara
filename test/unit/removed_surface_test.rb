# frozen_string_literal: true

require "test_helper"
require "open3"

# THE 2.1 DELETION, ASSERTED AS ABSENCE.
#
# Its predecessor (legacy_deletion_test.rb) SIMULATED the deletion -- copy
# lib/, `rm` the trees, probe entry points -- because the trees were still
# there. They are not, so the simulation harness went with them: what every
# canonical entry point still LOADS is already checked against the real lib/
# on every run by support_load_probe_test.rb.
#
# What nothing else checks is the negative, which is exactly the claim a bad
# rebase or an over-eager revert breaks quietly:
#
#   1. No removed path is back under lib/. Everything there is packaged
#      (see the gemspec's `spec.files` glob), so a restored file SHIPS.
#   2. A fresh process that loads the gem defines none of the removed names.
#
# THE GATE LINE. A probe that cannot tell the deleted tree from an intact one
# proves nothing -- an earlier lane's "green" run turned out to have measured
# the INTACT tree, because BUNDLE_GEMFILE pointed at the gemspec, which
# unshifts the real lib/ onto $LOAD_PATH ahead of any -I. Here the subject IS
# the real lib/, so the trap is the opposite one: the probe must prove it
# loaded THIS repo's lib/ and not some installed copy of the gem. It asserts
# that before it asserts any absence -- otherwise "the constant is gone" and
# "nothing was ever loaded" look identical.
class RemovedSurfaceTest < ActiveSupport::TestCase
  LIB = Pathname.new(File.expand_path("../../lib", __dir__))

  # The 2.1 `git rm`, verbatim. Anything on this list reappearing under lib/
  # is a shipped regression, not a local mess.
  REMOVED_PATHS = %w[
    capybara
    capybara_screenshot_diff
    capybara_screenshot_diff.rb
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
    snap_diff/removal.rb
    snap_diff/driver.rb
    snap_diff/drivers.rb
    snap_diff/drivers/chunky_png_driver.rb
    snap_diff/utils.rb
  ].freeze

  # NOT removed, and deliberately absent from the list above:
  # lib/capybara-screenshot-diff.rb. It looks like part of the v1 tree and is
  # not -- it is the Bundler entry point for the `capybara-screenshot-diff`
  # GEM NAME, which is still published (both names ship identical content).
  # Bundler.require requires the gem's own name, and the dash->slash fallback
  # it would otherwise use ("capybara/screenshot/diff") IS gone, so deleting
  # this file makes `gem "capybara-screenshot-diff"` a silent no-op followed by
  # a confusing NameError. support_load_probe_test pins both gem-name entries.

  # Removed CONSTANTS, by fully qualified name.
  REMOVED_CONSTANTS = %w[
    Capybara::Screenshot
    CapybaraScreenshotDiff
    SnapDiff::Deprecation
    SnapDiff::Removal
    SnapDiff::Driver
    SnapDiff::Utils
    SnapDiff::Drivers::ChunkyPNGDriver
    SnapDiff::Drivers::AVAILABLE_DRIVERS
  ].freeze

  # Removed METHODS on SnapDiff itself. `start` yielded the two v1 config
  # holders (SnapDiff.configure replaces it); `silence_deprecations` silenced
  # a channel that no longer exists.
  REMOVED_METHODS = %w[start silence_deprecations silence_deprecations=].freeze

  # Removed driver-registry methods. Named separately because SnapDiff::Drivers
  # SURVIVES as the namespace SnapDiff::Drivers::VipsDriver is published under
  # -- so "the module is gone" would be the wrong assertion.
  REMOVED_DRIVERS_METHODS = %w[loaded available for registry detect_available].freeze

  # Removed CONFIG settings. Absence here means NoMethodError at boot, which is
  # the point: `driver:` cannot select anything with one backend, and an
  # accept-and-ignore knob would let a config claim a backend choice that does
  # not exist.
  REMOVED_SETTINGS = %w[driver driver= shift_distance_limit shift_distance_limit=].freeze

  # Runs FIRST, before any absence assertion. Proves the process really loaded
  # THIS repo's lib/ -- otherwise every "constant is gone" below is vacuous.
  GATE_SCRIPT = <<~'RUBY'
    lib = ENV.fetch("LIB_UNDER_TEST")
    gate = []

    loaded = $LOADED_FEATURES.grep(%r{/lib/snap_diff(/|\.rb\z)})
    gate << "no snap_diff files loaded at all" if loaded.empty?

    # The BUNDLE_GEMFILE trap in reverse: files resolving from an INSTALLED
    # copy of the gem while the repo's lib/ sits unused on the load path.
    #
    # Anchored on the library path, NOT a bare /snap_diff/ substring: CI checks
    # this repo out at .../snap_diff-capybara/, so a bare match flags every gem
    # under vendor/bundle and the gate fails everywhere except a dev machine
    # whose directory happens to be named otherwise.
    strays = loaded.reject { |f| f.start_with?(lib) }
    gate << "loaded from outside the tree under test: #{strays.join(", ")}" unless strays.empty?

    # A positive control: something the gem still HAS must be present, or the
    # process is too broken for an absence to mean anything.
    gate << "SnapDiff.configure is missing -- the gem did not load" unless SnapDiff.respond_to?(:configure)
    gate << "VipsDriver is missing -- the only backend did not load" unless
      defined?(SnapDiff::Drivers::VipsDriver)

    unless gate.empty?
      abort("GATE: this process is NOT measuring the repo's lib/, so nothing below is evidence:\n- " + gate.join("\n- "))
    end
  RUBY

  test "no removed path is back under lib/" do
    back = REMOVED_PATHS.select { |path| LIB.join(path).exist? }

    assert_empty back, <<~MSG
      Path(s) 2.1 removed exist under lib/ again. Everything under lib/ is
      packaged, so this SHIPS:

      #{back.join("\n")}
    MSG
  end

  test "a fresh process loading the gem defines none of the removed names" do
    failure = probe(<<~RUBY)
      require "snap_diff"
      #{GATE_SCRIPT}

      back = []
      #{REMOVED_CONSTANTS.inspect}.each { |c| back << c if Object.const_defined?(c) }
      #{REMOVED_METHODS.inspect}.each { |m| back << "SnapDiff.\#{m}" if SnapDiff.respond_to?(m) }
      #{REMOVED_DRIVERS_METHODS.inspect}.each do |m|
        back << "SnapDiff::Drivers.\#{m}" if SnapDiff::Drivers.respond_to?(m)
      end
      #{REMOVED_SETTINGS.inspect}.each do |s|
        back << "SnapDiff.config.\#{s}" if SnapDiff.config.respond_to?(s)
      end

      abort("still defined: \#{back.join(", ")}") unless back.empty?
    RUBY

    assert_nil failure, <<~MSG
      A name 2.1 removed is defined again in a fresh process:

      #{failure}
    MSG
  end

  # The gate line has to be able to FAIL, or it is a comment with an `if`
  # around it. Same script, run with the repo's lib/ NOT on the load path and
  # LIB_UNDER_TEST still pointing at it: every absence assertion would pass
  # there (nothing is loaded, so nothing is defined), so only the gate can
  # reject it.
  test "the gate line rejects a process that never loaded the tree under test" do
    script = <<~RUBY
      module SnapDiff
        def self.configure = nil
      end
      #{GATE_SCRIPT}
    RUBY
    env = {"LIB_UNDER_TEST" => LIB.to_s, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "RUBYLIB" => nil}
    out, status = Open3.capture2e(env, RbConfig.ruby, "-e", script, chdir: Dir.tmpdir)

    assert_not status.success?, "the gate line passed on a process that loaded nothing"
    assert_includes out, "no snap_diff files loaded at all"
  end

  private

  # A fresh process with ONLY the repo's lib/ on the load path.
  #
  # `chdir: Dir.tmpdir` is the load-bearing half, and NOT a detail. Scrubbing
  # RUBYOPT/BUNDLE_GEMFILE is not sufficient on its own: with the cwd still
  # inside the project, RubyGems auto-discovers gems.rb, puts `-rbundler/setup`
  # BACK into RUBYOPT, and the gemspec unshifts lib/ ahead of the -I dir.
  # Running from a tmpdir means there is no gems.rb to find. Both defenses are
  # here because the gate line inside the script is the only thing that says so
  # out loud when they stop working.
  def probe(script)
    env = {"LIB_UNDER_TEST" => LIB.to_s, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "RUBYLIB" => nil}
    out, status = Open3.capture2e(
      env, RbConfig.ruby, "-I#{LIB}", "-e", script, chdir: Dir.tmpdir
    )

    out unless status.success?
  end
end
