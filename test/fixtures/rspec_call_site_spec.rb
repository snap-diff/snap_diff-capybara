# frozen_string_literal: true

# Run in a subprocess by test/unit/rspec_call_site_test.rb. Browser-free:
# ScreenshoterStub "captures" a fixture image, and each baseline is placed
# where a VCS checkout would put it. Deliberately does not require
# test_helper, whose minitest/autorun at_exit would take over this
# process's exit code.

require "tmpdir"
require "snap_diff"
require "snap_diff/integrations/rspec"

TEST_IMAGES_DIR = Pathname(File.expand_path("images", __dir__))
require "support/screenshoter_stub"

# Capture asks Capybara which driver it runs; rack_test needs an app.
Capybara.app = ->(_env) { [200, {}, [""]] }

RSpec.describe "a failed screenshot's call site", type: :feature do
  around do |example|
    Dir.mktmpdir do |root|
      SnapDiff.config.root = Pathname(root)
      SnapDiff.config.save_path = "doc/screenshots"
      SnapDiff.config.screenshoter = ScreenshoterStub
      SnapDiff.config.record = :once
      # Baselines are already in place, as a VCS checkout would leave them.
      SnapDiff::Vcs.define_singleton_method(:checkout_vcs) { |*| true }
      example.run
    end
  end

  # ScreenshoterStub captures images/<name without its _N suffix>.png;
  # the baseline is a different image, so each screenshot fails.
  def differing_baseline_for(name)
    dir = SnapDiff.config.root / SnapDiff.config.save_path
    FileUtils.mkdir_p(dir)
    FileUtils.cp(TEST_IMAGES_DIR / "a.png", dir / "#{name}.base.png")
  end

  it "fails two screenshots" do
    differing_baseline_for("b_1")
    differing_baseline_for("b_2")

    screenshot "b_1" # call site: screenshot
    expect(:page).to match_screenshot("b_2") # call site: match_screenshot
  end
end
