# frozen_string_literal: true

# A USER'S test file, run in its own process by
# test/integration/summary_line_test.rb: the user's requires, the user's
# `assert_matches_screenshot`, real Minitest, real git baselines. The
# summary line asserted on there is the one a real run prints -- an
# in-process assertion on `reporter.summary` would stay green through a
# regression that stopped the line from ever being printed.
#
# Env in:
#   SNAP_ROOT   -- a git repo whose `screenshots/` holds the COMMITTED baselines
#   SNAP_IMAGES -- directory holding the fixture PNGs a.png / b.png
#   SNAP_CASES  -- comma-separated subset of verified,changed,new (may be empty)
require "minitest/autorun"
require "snap_diff/integrations/minitest"
# The HTML report is a FEATURE and stays opt-in; the summary line is core
# honesty and must print either way. SNAP_NO_REPORTER runs the documented
# Rails setup, which registers no reporter at all.
require "snap_diff/reporters/html" unless ENV["SNAP_NO_REPORTER"]
require "fileutils"
require "pathname"

# No browser: rack-test is enough for the capture stub below, and Capybara
# refuses to build a session without an app.
Capybara.app = ->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] }

IMAGES = Pathname(ENV.fetch("SNAP_IMAGES"))
CASES = ENV.fetch("SNAP_CASES", "").split(",")

# The one stub: capture. Everything downstream of it -- baseline checkout,
# comparison, registry, reporters, finalize -- is the real thing.
class FileCopyScreenshoter < SnapDiff::Screenshoter
  # screenshot name => the image this "browser" returns for it
  CAPTURES = {
    "verified" => "a.png",
    "changed" => "b.png",
    "new" => "a.png"
  }.freeze

  def take_screenshot(screenshot_path)
    name = File.basename(screenshot_path.to_s).sub(/\.attempt_\d+/, "")
    FileUtils.mkdir_p(File.dirname(screenshot_path))
    FileUtils.cp(IMAGES / CAPTURES.fetch(File.basename(name, ".png")), screenshot_path)
  end
end

SnapDiff.config.root = ENV.fetch("SNAP_ROOT")
SnapDiff.config.save_path = "screenshots"
SnapDiff.config.screenshoter = FileCopyScreenshoter
SnapDiff.config.fail_if_new = false

class SummaryLineCase < Minitest::Test
  include SnapDiff::Minitest::Assertions

  CASES.each do |name|
    define_method(:"test_#{name}") { assert_matches_screenshot(name) }
  end
end
