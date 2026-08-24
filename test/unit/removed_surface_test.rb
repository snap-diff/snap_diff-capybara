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

  # The 2.1 `git rm`, verbatim -- the IMPLEMENTATION files. Anything on this
  # list reappearing under lib/ is a shipped regression, not a local mess.
  #
  # The line moved on 2026-08-24 (ADR-008 amendment) and it moved by exactly
  # one category: the v1 REQUIRE PATHS are back as one-line alias entries
  # (lib/capybara/screenshot/diff.rb, lib/capybara_screenshot_diff{,/*}.rb),
  # because four of six discoverable real users import the gem under them and
  # a LoadError there fires before any constant alias could help. What those
  # files must never contain again is what is listed here: the v1 tree that
  # held logic, the deprecation channel, and the driver abstraction.
  # compat_surface_test pins the entries; this pins their emptiness.
  REMOVED_PATHS = %w[
    capybara/screenshot/diff
    capybara_screenshot_diff/snap.rb
    capybara_screenshot_diff/snap_manager.rb
    capybara_screenshot_diff/screenshot_assertion.rb
    capybara_screenshot_diff/screenshot_namer.rb
    capybara_screenshot_diff/attempts_reporter.rb
    capybara_screenshot_diff/static.rb
    capybara_screenshot_diff/reporters
    capybara_screenshot_diff/error_with_filtered_backtrace.rb
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
    snap_diff/removal.rb
    snap_diff/driver.rb
    snap_diff/drivers.rb
    snap_diff/drivers/chunky_png_driver.rb
    snap_diff/utils.rb
  ].freeze

  # Alias-only by contract: three lines of comment and one `require`. A v1
  # entry file that grows a `def` or a constant assignment has stopped being
  # an alias and started being the tree 2.1 deleted.
  ALIAS_ENTRIES = %w[
    capybara/screenshot/diff.rb
    capybara_screenshot_diff.rb
    capybara_screenshot_diff/dsl.rb
    capybara_screenshot_diff/minitest.rb
    capybara_screenshot_diff/rspec.rb
    capybara_screenshot_diff/cucumber.rb
  ].freeze

  # NOT removed, and deliberately absent from the list above:
  # lib/capybara-screenshot-diff.rb. It looks like part of the v1 tree and is
  # not -- it is the Bundler entry point for the `capybara-screenshot-diff`
  # GEM NAME, which is still published (both names ship identical content).
  # support_load_probe_test pins both gem-name entries.

  # Removed CONSTANTS, by fully qualified name.
  #
  # Capybara::Screenshot and CapybaraScreenshotDiff are NOT here since the
  # ADR-008 amendment: they survive as permanent eager same-object aliases of
  # SnapDiff (snap_diff/compat.rb), pinned by compat_surface_test. What is
  # listed here is the machinery those names used to carry.
  REMOVED_CONSTANTS = %w[
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

  # `driver` / `shift_distance_limit` used to be listed here as removed
  # settings whose absence was asserted. The ADR-008 amendment reversed that:
  # deleting a setting a real config writes is a SILENT failure (one known
  # user guards the writer with `respond_to?`), so they are raising stubs now
  # rather than gone. compat_surface_test owns them.

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

  test "the v1 require paths are alias entries, not the tree that was deleted" do
    logic = ALIAS_ENTRIES.filter_map do |entry|
      file = LIB.join(entry)
      next "#{entry}: missing -- a real user's `require` line now LoadErrors" unless file.exist?

      code = file.read.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      offending = code.grep_v(/\Arequire /)
      "#{entry}: #{offending.join(" / ")}" unless offending.empty?
    end

    assert_empty logic, <<~MSG
      A v1 entry file is missing, or has grown something other than a
      `require`. These are alias entries: they exist so a real user's require
      line resolves, not to hold the surface 2.1 deleted.

      #{logic.join("\n")}
    MSG
  end

  # --- The release pipeline is a consumer of this deletion too ---------
  #
  # release.yml verified the version by executing
  # `ruby -I lib -r capybara/screenshot/diff/version -e "puts
  # Capybara::Screenshot::Diff::VERSION"`. 2.1 deleted that file, so the FIRST
  # 2.1 release would have failed at "Verify version" -- a release workflow
  # broken by the release it is releasing, discovered at the worst moment.
  #
  # Generic on purpose: it extracts every inline `ruby -I lib -r ... -e ...`
  # from .github and RUNS it, so the next one is covered without an edit here.
  WORKFLOW_RUBY = /ruby -I lib -r (\S+) -e "([^"]*)"/

  test "every inline ruby the CI workflows run still loads and prints what it claims" do
    invocations = github_files.flat_map do |rel, file|
      file.read.scan(WORKFLOW_RUBY).map { |path, script| [rel, path, script] }
    end

    assert_not_empty invocations, "no inline ruby found in .github -- this gate would pass vacuously"

    failures = invocations.filter_map do |rel, path, script|
      out, status = Open3.capture2e(
        {"RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil},
        RbConfig.ruby, "-I", "lib", "-r", path, "-e", script, chdir: PROJECT_ROOT.to_s
      )
      "#{rel}: `ruby -I lib -r #{path} -e \"#{script}\"` -> #{out.strip}" unless status.success?
    end

    assert_empty failures, <<~MSG
      A workflow executes ruby against something this release removed. It
      fails on the release it is releasing:

      #{failures.join("\n")}
    MSG
  end

  test "the release workflow verifies the version against the namespace the gem still ships" do
    workflow = PROJECT_ROOT.join(".github/workflows/release.yml").read
    command = workflow[/CODE_VERSION=\$\(([^)]+)\)/, 1]

    assert command, "release.yml no longer computes CODE_VERSION the way this gate reads it"

    out, status = Open3.capture2e(
      {"RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil},
      "/bin/sh", "-c", command, chdir: PROJECT_ROOT.to_s
    )

    assert status.success?, "release.yml's version check does not run: #{out}"
    # Last line only: the shell resolves `ruby` through whatever shim the
    # developer's version manager installed, and some of them chatter first.
    assert_equal SnapDiff::VERSION, out.lines.last.to_s.strip
  end

  # The non-executable half: a workflow, action or issue template that merely
  # NAMES something removed is not caught above and quietly misinforms.
  # `capybara_screenshot_diff/` is excluded from the alternation -- those four
  # require paths survive as alias entries (see ALIAS_ENTRIES).
  GITHUB_REMOVED_MENTIONS = %r{
    capybara/screenshot/diff/
    |chunky_?png
    |SCREENSHOT_DRIVER
    |shift_distance_limit
  }xi

  test "nothing under .github names a file or setting this release removed" do
    files = github_files
    assert_not_empty files, "the .github scan matched nothing -- it would pass vacuously"

    offenders = files.flat_map do |rel, file|
      file.read.lines.each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?("#")

        "#{rel}:#{index + 1}: #{line.strip}" if GITHUB_REMOVED_MENTIONS.match?(line)
      end
    end

    assert_empty offenders, <<~MSG
      CI configuration names something 2.1 removed. Nothing executes these
      lines, so nothing else will ever say they are wrong:

      #{offenders.join("\n")}
    MSG
  end

  private

  PROJECT_ROOT = Pathname.new(File.expand_path("../..", __dir__))

  # [relative path, Pathname] for every file under .github/.
  def github_files
    Dir[".github/**/*", base: PROJECT_ROOT.to_s]
      .map { |rel| [rel, PROJECT_ROOT.join(rel)] }
      .select { |_rel, file| file.file? }
  end

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
