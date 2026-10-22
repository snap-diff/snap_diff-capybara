# frozen_string_literal: true

require "test_helper"
require "snap_diff/reporters/html"
require "support/setup_capybara_drivers"

# The report's review controls, driven in a real browser: a reviewer clicks
# Accept and Reject and the read-only field shows the PR comment command.
class ReviewControlsTest < ActiveSupport::TestCase
  # Pinned: CI sets these for real. No GITHUB_REF unless a test sets one.
  CI_ENV = {"GITHUB_RUN_ID" => "99", "GITHUB_REF" => nil, "GITHUB_REPOSITORY" => "o/r", "GITHUB_SERVER_URL" => "https://github.com"}.freeze

  setup do
    @dir = Pathname.new(Dir.mktmpdir).realpath
    system("git", "-C", @dir.to_s, "init", "-q", exception: true)
    @original_root = SnapDiff.config.root
    SnapDiff.config.root = @dir
    @original_env = CI_ENV.keys.to_h { |k| [k, ENV[k]] }
    CI_ENV.each { |k, v| ENV[k] = v }
    @session = Capybara::Session.new(Capybara.javascript_driver)
  end

  teardown do
    @session.quit
    @original_env.each { |k, v| ENV[k] = v }
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

  test "Commit decisions opens the prefilled new-issue page in a new tab" do
    ENV["GITHUB_REF"] = "refs/pull/313/merge"
    visit_with_window_open_spy(write_report(%w[one two three]))
    assert @session.has_button?("Commit decisions", disabled: true), "nothing to commit yet"

    @session.find("body").send_keys("y", :right, "n", :right, "y")
    @session.click_button "Commit decisions"

    url, target, features = opened
    assert_equal ["_blank", "noopener"], [target, features]
    assert_equal "https://github.com/o/r/issues/new", url[/\A[^?]*/]
    assert_equal({"title" => "snap-diff review: PR #313 (run 99)",
                  "body" => "/snap-diff accept run=99 pr=313 screenshots/one.png@#{sha16} screenshots/three.png@#{sha16}\n" \
                            "/snap-diff reject screenshots/two.png"}, query(url))
    assert @session.has_css?("#review-hint", text: "Opens a GitHub issue with your decisions; submit it to commit.")
  end

  test "a reject-only review names the run and PR on its reject line" do
    ENV["GITHUB_REF"] = "refs/pull/313/merge"
    visit_with_window_open_spy(write_report(%w[one two]))

    @session.find("body").send_keys("n")
    @session.click_button "Commit decisions"

    assert_equal "/snap-diff reject run=99 pr=313 screenshots/one.png", query(opened.first)["body"]
    assert_equal "/snap-diff reject run=99 pr=313 screenshots/one.png", command
  end

  test "without a PR in the run the command and title leave it out" do
    ENV["GITHUB_REF"] = "refs/heads/main"
    visit_with_window_open_spy(write_report(%w[one]))

    @session.find("body").send_keys("y")
    @session.click_button "Commit decisions"

    assert_equal({"title" => "snap-diff review: (run 99)", "body" => "/snap-diff accept run=99 screenshots/one.png@#{sha16}"}, query(opened.first))
  end

  test "a link too long for GitHub leaves only the copy fallback" do
    names = (1..40).map { |i| "#{"long" * 45}#{i}" } # ~190-char names: 40 accepts pass 7000 chars
    visit_with_window_open_spy(write_report(names))

    @session.find("body").send_keys(*names.flat_map { ["y", :right] })

    assert @session.has_button?("Commit decisions", disabled: true)
    assert @session.has_css?("#review-commit-note", text: "Too many files for one link: copy the command and paste it as a PR comment.")
    assert_equal 40, command.scan("@#{sha16}").size, "the command itself is complete"
    assert @session.has_button?("Copy review command")
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

  def visit_with_window_open_spy(report)
    @session.visit "file://#{report}"
    @session.execute_script("window.open = function(u, t, f) { window.__opened = [u, t, f]; return null; }")
  end

  def opened = @session.evaluate_script("window.__opened")

  def query(url) = URI.decode_www_form(URI(url).query).to_h

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
