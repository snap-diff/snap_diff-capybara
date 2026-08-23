# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"
require "fileutils"
require "unit/support_load_probe_test" # single source of truth for the canonical entry-point tables

# THE 2.1 DELETION, ACTUALLY RUN.
#
# legacy_tree_is_alias_only_test.rb and core_tree_has_no_legacy_deps_test.rb
# are STATIC proxies for one claim: `git rm` the v1 surface and the gem still
# loads. This test stops proxying. It copies lib/ to a tmpdir, performs the
# deletion, applies the edits the deletion needs, and requires every canonical
# entry point in a fresh subprocess.
#
# THE GATE LINE (see GATE_SCRIPT) is why this is evidence rather than
# decoration. An earlier lane's "green" run turned out to have measured the
# INTACT tree: BUNDLE_GEMFILE pointed at the gemspec, which unshifts the real
# lib/ onto $LOAD_PATH ahead of any -I. A run that cannot tell the deleted
# tree from the intact one proves nothing, so before asserting anything about
# the surface every probe HARD-ASSERTS that the deletion is in effect -- the
# deleted names are gone AND every snap_diff file that loaded came from the
# tmpdir. The subprocess is isolated from bundler as well (see #probe), but
# that isolation is precisely the thing that silently stopped working last
# time -- the gate line is what notices when it does.
class LegacyDeletionTest < ActiveSupport::TestCase
  PROJECT_ROOT = Pathname.new(File.expand_path("../..", __dir__))

  # The 2.1 `git rm`, verbatim from the Rakefile's header comment (minus
  # test/legacy, which this test does not load).
  DELETED = %w[
    capybara
    capybara_screenshot_diff
    capybara-screenshot-diff.rb
    capybara_screenshot_diff.rb
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
  ].freeze

  # The edits the deletion needs, as [file, exact line to remove or replace,
  # replacement or nil]. Exact-match on purpose: if one of these lines is
  # reworded, the edit must go red here rather than silently not applying and
  # leaving the probe to fail somewhere confusing.
  EDITS = [
    # The one line in the canonical entry point that 2.1 drops.
    ["snap_diff.rb", %(require "snap_diff/legacy_shims"), nil],
    # The new gem name's Bundler entry point is KEPT, repointed off the v1
    # umbrella. It matches neither gate's file glob, so this is the only
    # thing that checks its post-2.1 shape at all.
    ["snap_diff-capybara.rb",
      %(require "capybara_screenshot_diff/minitest"),
      %(require "snap_diff/integrations/minitest")]
  ].freeze

  ENTRY_POINTS = SupportLoadProbeTest::CANONICAL_ENTRY_POINTS

  # Runs FIRST in every probe, before a single surface assertion. Proves the
  # process is looking at the deleted tree and nothing else.
  GATE_SCRIPT = <<~'RUBY'
    tree = ENV.fetch("DELETED_TREE")
    gate = []

    # Defined in legacy_shims.rb; its presence means the deletion did not take.
    gate << "SnapDiff.start is still defined" if SnapDiff.respond_to?(:start)
    gate << "CapybaraScreenshotDiff is still defined" if defined?(CapybaraScreenshotDiff)

    deleted = $LOADED_FEATURES.grep(%r{/snap_diff/(legacy_shims|deprecation)\.rb\z})
    gate << "deleted files loaded: #{deleted.join(", ")}" unless deleted.empty?

    v1 = $LOADED_FEATURES.grep(%r{/lib/capybara(-screenshot-diff|_screenshot_diff|/screenshot)})
    gate << "v1 tree loaded: #{v1.join(", ")}" unless v1.empty?

    # The BUNDLE_GEMFILE trap: files resolving from the INTACT lib/ while the
    # tmpdir sits unused on the load path.
    #
    # Anchored on the library path, NOT a bare /snap_diff/ substring: CI checks
    # this repo out at .../snap_diff-capybara/, so a bare match flags every gem
    # under vendor/bundle (nokogiri and friends) and the gate fails everywhere
    # except a dev machine whose directory happens to be named otherwise.
    strays = $LOADED_FEATURES.grep(%r{/lib/snap_diff(/|\.rb\z)}).reject { |f| f.start_with?(tree) }
    gate << "loaded from outside the deleted tree: #{strays.join(", ")}" unless strays.empty?

    unless gate.empty?
      abort("GATE: this process is NOT running the deleted tree, so nothing below is evidence:\n- " + gate.join("\n- "))
    end
  RUBY

  test "every canonical entry point loads and keeps its surface after the 2.1 deletion" do
    in_deleted_tree do |tree|
      failures = ENTRY_POINTS.filter_map do |entry, methods|
        probe(tree, <<~RUBY)
          require #{entry.inspect}
          #{GATE_SCRIPT}
          missing = #{methods.inspect}.reject { |m| SnapDiff.respond_to?(m) }
          missing << "VERSION" unless defined?(SnapDiff::VERSION)
          abort("missing: \#{missing.join(", ")}") unless missing.empty?
        RUBY
      end

      assert_empty failures, <<~MSG
        `git rm` of the v1 surface breaks canonical entry point(s) -- 2.1 is a
        refactor, not a deletion, until these load:

        #{failures.join("\n")}
      MSG
    end
  end

  test "every canonical entry point defines its advertised constants after the 2.1 deletion" do
    in_deleted_tree do |tree|
      failures = SupportLoadProbeTest::CANONICAL_ADVERTISED_CONSTANTS.filter_map do |entry, constants|
        probe(tree, <<~RUBY)
          require #{entry.inspect}
          #{GATE_SCRIPT}
          missing = #{constants.inspect}.reject { |c| Object.const_defined?(c) }
          abort("missing: \#{missing.join(", ")}") unless missing.empty?
        RUBY
      end

      assert_empty failures, <<~MSG
        Entry point(s) lose their advertised constants once the v1 surface is deleted:

        #{failures.join("\n")}
      MSG
    end
  end

  # The gate line has to be able to FAIL, or it is a comment with an `if`
  # around it. Same probe, run against an UNTOUCHED copy of lib/: every
  # surface assertion would pass there, so only the gate can reject it.
  test "the gate line rejects an intact tree" do
    Dir.mktmpdir("snapdiff_intact") do |dir|
      tree = copy_lib_to(dir)

      failure = probe(tree, <<~RUBY)
        require "snap_diff"
        #{GATE_SCRIPT}
      RUBY

      assert failure, "the gate line passed on an INTACT tree -- it cannot distinguish the deletion"
      assert_includes failure, "SnapDiff.start is still defined"
    end
  end

  private

  # $LOADED_FEATURES holds resolved real paths, and Dir.mktmpdir hands back
  # the symlinked /var form on macOS -- so the gate's "outside the tree"
  # check compared /private/var/... against /var/... and rejected the very
  # tree it had just built. Resolve once, here.
  def copy_lib_to(dir)
    FileUtils.cp_r(PROJECT_ROOT.join("lib").to_s, File.join(dir, "lib"))
    File.realpath(File.join(dir, "lib"))
  end

  # Yields the path to a lib/ with the 2.1 deletion applied.
  def in_deleted_tree
    Dir.mktmpdir("snapdiff_deleted") do |dir|
      tree = copy_lib_to(dir)

      DELETED.each do |path|
        target = File.join(tree, path)
        assert File.exist?(target), "2.1 deletion set names #{path}, which does not exist"
        FileUtils.rm_rf(target)
      end

      EDITS.each do |file, line, replacement|
        target = Pathname.new(File.join(tree, file))
        source = target.read

        assert_includes source, line, "2.1 edit for #{file} no longer matches the file"
        target.write(source.sub(line + "\n", replacement ? replacement + "\n" : ""))
      end

      yield tree
    end
  end

  # A fresh process with ONLY +tree+ on the load path.
  #
  # `chdir: tree` is the load-bearing half, and NOT a detail. Scrubbing
  # RUBYOPT/BUNDLE_GEMFILE is not sufficient on its own: with the cwd still
  # inside the project, RubyGems auto-discovers gems.rb, puts
  # `-rbundler/setup` BACK into RUBYOPT, and the gemspec unshifts the real
  # lib/ ahead of the -I dir -- measured, this exact scrub with cwd at the
  # project root loads 24 files from the intact tree. Running from the
  # tmpdir means there is no gems.rb to find. Both defenses are here because
  # the gate line inside the script is the only one that says so out loud
  # when they stop working.
  def probe(tree, script)
    preamble = <<~RUBY
      $LOAD_PATH.unshift(#{tree.inspect})
      #{SupportLoadProbeTest::CUCUMBER_RUNTIME_STUB}
    RUBY
    env = {"DELETED_TREE" => tree, "RUBYOPT" => nil, "BUNDLE_GEMFILE" => nil, "RUBYLIB" => nil}
    out, status = Open3.capture2e(env, RbConfig.ruby, "-e", preamble + script, chdir: tree)

    "#{script.lines.first.strip} -> #{out}" unless status.success?
  end
end
