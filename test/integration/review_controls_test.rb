# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/html"
require "support/setup_capybara_drivers"

# The report's review controls, driven in a real browser: a reviewer clicks
# Accept and Reject and the read-only field shows the PR comment command.
class ReviewControlsTest < ActiveSupport::TestCase
  setup do
    @dir = Pathname.new(Dir.mktmpdir).realpath
    system("git", "-C", @dir.to_s, "init", "-q", exception: true)
    @original_root = SnapDiff.config.root
    SnapDiff.config.root = @dir
    @original_run_id = ENV["GITHUB_RUN_ID"]
    ENV["GITHUB_RUN_ID"] = "99"
    @session = Capybara::Session.new(Capybara.javascript_driver)
  end

  teardown do
    @session.quit
    ENV["GITHUB_RUN_ID"] = @original_run_id
    SnapDiff.config.root = @original_root
    FileUtils.remove_entry(@dir)
  end

  test "Accept and Reject build the exact PR comment command" do
    # "one" and "one again" are two entries of the same file.
    report = write_report(%w[one one_again two], files: {"one_again" => "one"})
    @session.visit "file://#{report}"

    assert_equal "", command, "nothing is decided yet"
    @session.click_button "Accept"
    assert_equal "/snap-diff accept run=99 screenshots/one.png", command
    assert_equal "1 accepted · 0 rejected", @session.find("#review-count").text

    @session.find("body").send_keys(:right) # one_again: shares the decision
    assert @session.has_css?("#review-accept.active")

    @session.find("body").send_keys(:right)
    @session.click_button "Reject"
    assert_equal "/snap-diff accept run=99 screenshots/one.png\n/snap-diff reject screenshots/two.png", command
    assert_equal "1 accepted · 1 rejected", @session.find("#review-count").text

    @session.click_button "Accept" # two: reject -> accept
    assert_equal "/snap-diff accept run=99 screenshots/one.png screenshots/two.png", command

    @session.find("body").send_keys("n")
    assert_equal "/snap-diff accept run=99 screenshots/one.png\n/snap-diff reject screenshots/two.png", command
  end

  test "a local report has no review controls" do
    ENV["GITHUB_RUN_ID"] = nil
    @session.visit "file://#{write_report(%w[one])}"

    assert @session.has_css?("#topbar-title", text: "one")
    assert @session.has_no_button?("Accept")
    assert @session.has_no_css?("#review-command")
  end

  private

  def command = @session.find("#review-command").value

  def write_report(names, files: {})
    reporter = SnapDiff::Reporters::HTML.new(output_path: @dir / "report.html")
    names.each do |name|
      path = @dir / "screenshots" / "#{files.fetch(name, name)}.png"
      path.dirname.mkpath
      FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), path)
      reporter.record([SnapDiff::ScreenshotAssertion.new(name, path: path)])
    end
    reporter.finalize.to_s
  end
end
