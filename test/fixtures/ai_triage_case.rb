# frozen_string_literal: true

# A USER'S test file with AI triage enabled, run in its own process by
# test/integration/ai_triage_test.rb: real registry, real reporters, real
# git baselines, real Minitest. The only stubs are capture (a file copy)
# and the AI backend (a name-keyed fake -- no model download, no network).
#
# Env in:
#   SNAP_ROOT    -- a git repo whose `screenshots/` holds the COMMITTED baselines
#   SNAP_IMAGES  -- directory holding the fixture PNGs a.png / b.png
#   SNAP_CASES   -- comma-separated subset of verified,flaky,buggy (may be empty)
#   SNAP_FAIL_ON -- when "1", the reporter gates with fail_on: %w[real_bug]
require "minitest/autorun"
require "snap_diff/integrations/minitest"
require "snap_diff/reporters/html"
require "snap_diff/reporters/ai_simple"
require "fileutils"
require "pathname"

# No browser: rack-test is enough for the capture stub below.
Capybara.app = ->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] }

IMAGES = Pathname(ENV.fetch("SNAP_IMAGES"))
CASES = ENV.fetch("SNAP_CASES", "").split(",")

# verified: capture equals the baseline. flaky/buggy: capture differs.
class FileCopyScreenshoter < SnapDiff::Screenshoter
  CAPTURES = {"verified" => "a.png", "flaky" => "b.png", "buggy" => "b.png"}.freeze

  def take_screenshot(screenshot_path)
    name = File.basename(screenshot_path.to_s).sub(/\.attempt_\d+/, "")
    FileUtils.mkdir_p(File.dirname(screenshot_path))
    FileUtils.cp(IMAGES / CAPTURES.fetch(File.basename(name, ".png")), screenshot_path)
  end
end

# The fake backend: similarity keyed by screenshot name -- flaky lands in
# the flaky band, buggy in the real_bug band.
FAKE_BACKEND = ->(name:, base:, current:, meta:) {
  {similarity: {"flaky" => 0.999, "buggy" => 0.42}.fetch(name, 0.5)}
}

SnapDiff.config.root = ENV.fetch("SNAP_ROOT")
SnapDiff.config.save_path = "screenshots"
SnapDiff.config.screenshoter = FileCopyScreenshoter
SnapDiff.config.fail_if_new = false

options = (ENV["SNAP_FAIL_ON"] == "1") ? {fail_on: %w[real_bug]} : {}
SnapDiff::Reporting.register(SnapDiff::Reporters::AISimple.new(backend: FAKE_BACKEND, **options))

class AiTriageCase < Minitest::Test
  include SnapDiff::Minitest::Assertions

  CASES.each do |name|
    define_method(:"test_#{name}") { assert_matches_screenshot(name) }
  end
end
