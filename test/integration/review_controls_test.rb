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
    @session.visit "file://#{write_report(%w[one two three])}"

    assert_equal "", command, "nothing is decided yet"
    assert_equal %w[false false], pressed
    @session.find("body").send_keys(:right, :right, "y") # the user's flow: 3rd Y, 2nd N, 1st Y
    @session.find("body").send_keys(:left, "n")
    @session.find("body").send_keys(:left, "y")

    assert_equal "/snap-diff accept run=99 screenshots/one.png@#{sha16} screenshots/three.png@#{sha16}\n" \
      "/snap-diff reject screenshots/two.png", command
    assert_equal "2 accepted · 1 rejected", @session.find("#review-count").text
    assert_equal %w[true false], pressed, "one is accepted"

    @session.click_button "Reject" # one: accept -> reject
    assert_equal %w[false true], pressed
    assert_equal "/snap-diff accept run=99 screenshots/three.png@#{sha16}\n" \
      "/snap-diff reject screenshots/one.png screenshots/two.png", command

    @session.click_button "Reject" # one: reject -> undecided
    assert_equal %w[false false], pressed
    assert_equal "/snap-diff accept run=99 screenshots/three.png@#{sha16}\n/snap-diff reject screenshots/two.png", command
  end

  test "an earlier capture of a file points at the last one, which alone has the buttons" do
    # "one" and "one_again" capture the same file; only the last is on disk.
    @session.visit "file://#{write_report(%w[one one_again], files: {"one_again" => "one"})}"

    assert @session.has_no_button?("Accept")
    assert @session.has_css?("#review-note", text: "Superseded by a later capture of this file.")
    @session.find("body").send_keys("y")
    assert_equal "", command, "Y does nothing on a superseded entry"

    @session.click_button "Show it"
    assert @session.has_css?("#topbar-title", text: "one_again")
    assert @session.has_no_css?("#review-note")
    @session.click_button "Accept"
    assert_equal "/snap-diff accept run=99 screenshots/one.png@#{sha16}", command
  end

  test "an entry with no final capture says why it cannot be accepted" do
    @session.visit "file://#{write_report(%w[gone], missing: %w[gone])}"

    assert @session.has_css?("#review-note", text: "No final capture in this report, so it cannot be accepted here.")
    assert @session.has_no_button?("Accept")
    @session.find("body").send_keys("y")
    assert_equal "", command
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

  # aria-pressed of [Accept, Reject], which must follow the visual state.
  def pressed = %w[#review-accept #review-reject].map { |id| @session.find(id)["aria-pressed"] }

  # The same bytes (a.png) for every capture, so one hash.
  def sha16 = Digest::SHA256.file(File.expand_path("a.png", TEST_IMAGES_DIR)).hexdigest[0, 16]

  def write_report(names, files: {}, missing: [])
    reporter = SnapDiff::Reporters::HTML.new(output_path: @dir / "report.html")
    names.each do |name|
      path = @dir / "screenshots" / "#{files.fetch(name, name)}.png"
      path.dirname.mkpath
      FileUtils.cp(File.expand_path("a.png", TEST_IMAGES_DIR), path) unless missing.include?(name)
      reporter.record([SnapDiff::ScreenshotAssertion.new(name, path: path)])
    end
    reporter.finalize.to_s
  end
end
