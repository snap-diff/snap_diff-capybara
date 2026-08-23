# frozen_string_literal: true

require "test_helper"
require "open3"

# What is left of deletion_3_0_test.rb once the deletion is real.
#
# That test SIMULATED the removal -- copy lib/ to a tmpdir, delete the v1
# trees, apply the two edits, probe every canonical entry point in a fresh
# process -- because the trees were still there. They are not. Every
# entry-point claim it made is now measured against the real lib/ by
# support_load_probe_test.rb on every run, so the simulation harness (and
# its gate line, which existed to prove the simulation was looking at the
# deleted tree) went with the trees.
#
# One claim survives it, and nothing else covers it: ABSENCE. lib/**/*.rb is
# packaged wholesale, so a v1 file brought back by a bad rebase or an
# incomplete `git rm` ships to users; and a constant redefined under an old
# name makes the gem quietly support a surface documented as removed.
class LegacySurfaceRemovedTest < ActiveSupport::TestCase
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  LIB = Pathname.new(PROJECT_ROOT).join("lib")

  # The 2.1 `git rm`, minus test/legacy (deleted with the same commit; a
  # test tree is not packaged and cannot come back unnoticed).
  REMOVED_PATHS = %w[
    capybara
    capybara_screenshot_diff
    capybara-screenshot-diff.rb
    capybara_screenshot_diff.rb
    snap_diff/legacy_shims.rb
    snap_diff/deprecation.rb
  ].freeze

  test "no removed file is back under lib/" do
    resurrected = REMOVED_PATHS.select { |path| LIB.join(path).exist? }

    assert_empty resurrected, <<~MSG
      The v1 compatibility trees were removed in 2.1, but lib/ carries these
      again. Everything under lib/ is packaged, so whatever is here ships:

      #{resurrected.join("\n")}
    MSG
  end

  # A subprocess because test_helper.rb loads the whole gem plus its
  # support files, any of which could define one of these names and mask a
  # gem that no longer does.
  test "a fresh process loading the gem defines none of the removed names" do
    script = <<~'RUBY'
      require "snap_diff"
      require "snap_diff/integrations/minitest"

      back = []
      back << "Capybara::Screenshot" if defined?(Capybara::Screenshot)
      back << "CapybaraScreenshotDiff" if defined?(CapybaraScreenshotDiff)
      back << "SnapDiff::Deprecation" if defined?(SnapDiff::Deprecation)
      back << "SnapDiff.start" if SnapDiff.respond_to?(:start)
      back << "SnapDiff.silence_deprecations" if SnapDiff.respond_to?(:silence_deprecations)

      abort("still defined: #{back.join(", ")}") unless back.empty?
    RUBY

    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script, chdir: PROJECT_ROOT)

    assert status.success?, <<~MSG
      The removed v1 surface is reachable again from a plain require. 2.1
      dropped it deliberately (ADR-008: SnapDiff.configure is the single
      config entry point) and docs/UPGRADING.md tells users it is gone:

      #{out}
    MSG
  end
end
