# frozen_string_literal: true

require "test_helper"
require "base64"
require "support/setup_capybara_drivers"
require "support/fake_github_api"

# Drives lib/snap_diff/review/index.html in a real browser against a fake
# GitHub API. The page is a black box: only what it shows and what it sends.
class ReviewPageTest < Minitest::Test
  TOKEN = "ghp_test_token"
  HOMEPAGE = "doc/screenshots/linux/homepage.png"
  SIGNUP = "doc/screenshots/linux/signup.png"

  def setup
    @homepage_png = File.binread(TEST_IMAGES_DIR / "a.png")
    @signup_png = File.binread(TEST_IMAGES_DIR / "c.png")
    @baseline_png = File.binread(TEST_IMAGES_DIR / "b.png")
  end

  def teardown
    @session&.quit
  end

  def test_accept_one_reject_one_commits_exact_bytes_and_comments
    review do |fake|
      fake.baselines[HOMEPAGE] = @baseline_png
    end
    page.find("#list button", text: "homepage").click
    page.click_button "Accept", exact: true
    page.find("#list button", text: "signup").click
    page.click_button "Reject", exact: true
    submit

    page.assert_text "Done. 1 accepted, 1 rejected."
    sent = fake.requests
    blob = only(sent, "POST", "/repos/o/r/git/blobs").json
    assert_equal "base64", blob[:encoding]
    assert_equal @homepage_png, Base64.strict_decode64(blob[:content])

    tree = only(sent, "POST", "/repos/o/r/git/trees").json
    assert_equal [HOMEPAGE], tree[:tree].map { _1[:path] }
    assert_equal fake.git_sha("tree of head"), tree[:base_tree]

    commit = only(sent, "POST", "/repos/o/r/git/commits").json
    assert_equal [FakeGithub::HEAD_SHA], commit[:parents]

    patch = only(sent, "PATCH", "/repos/o/r/git/refs/heads/feature").json
    assert_equal false, patch[:force]
    assert_equal fake.git_sha(commit.to_json), patch[:sha]

    comment = only(sent, "POST", "/repos/o/r/issues/7/comments").json[:body]
    assert_includes comment, "homepage"
    assert_includes comment, "signup"

    assert_equal ["Bearer #{TOKEN}"], sent.map(&:authorization).uniq
    page.assert_selector :link, "Commit #{patch[:sha][0, 7]}", href: "https://github.com/o/r/commit/#{patch[:sha]}"
  end

  def test_artifact_from_another_run_is_refused_before_download
    review { |fake| fake.artifact[:workflow_run][:id] = 99 }

    page.assert_text "was not made by CI run 11"
    refute_includes fake.requests.map(&:path), "/repos/o/r/actions/artifacts/22/zip"
    assert_empty fake.writes
  end

  def test_pr_head_that_moved_since_the_run_is_refused_before_download
    review { |fake| fake.pull[:head][:sha] = "b2" * 20 }

    page.assert_text "has new commits since CI run 11"
    refute_includes fake.requests.map(&:path), "/repos/o/r/actions/artifacts/22/zip"
    assert_empty fake.writes
  end

  def test_branch_that_moved_between_load_and_submit_is_reported_and_not_commented
    review do |fake|
      fake.baselines[HOMEPAGE] = @baseline_png
      fake.patch_status = 422
      fake.moved_ref_sha = "c3" * 20
    end
    page.find("#list button", text: "homepage").click
    page.click_button "Accept", exact: true
    submit

    page.assert_text "This PR has new commits since CI run 11"
    assert_equal 1, fake.requests.count { _1.method == "PATCH" }
    assert_empty fake.requests.select { _1.path.end_with?("/comments") }
  end

  def test_malicious_manifest_entries_cannot_be_accepted_or_written
    entries = [
      {name: "rake", status: "new", path: "Rakefile", file: "good.png"},
      {name: "workflow", status: "new", path: ".github/x.png", file: "good.png"},
      {name: "fake", status: "new", path: "doc/fake.png", file: "fake.png"},
      {name: "fine", status: "new", path: "doc/fine.png", file: "good.png"}
    ]
    review(entries: entries, files: {"good.png" => @signup_png, "fake.png" => "not a png at all"})

    page.assert_text "Left out 3 screenshot(s)"
    page.assert_text "refusing path Rakefile"
    page.assert_text "refusing path .github/x.png"
    page.assert_text "fake.png is not a real .png image"
    page.assert_selector "#list button", count: 1
    page.click_button "Accept", exact: true
    submit

    page.assert_text "Done. 1 accepted, 0 rejected."
    tree = only(fake.requests, "POST", "/repos/o/r/git/trees").json
    assert_equal ["doc/fine.png"], tree[:tree].map { _1[:path] }
  end

  def test_bad_token_asks_for_the_token_again_and_requests_nothing_else
    review { |fake| fake.runs_status = 401 }

    page.assert_text "The token is invalid or expired"
    page.assert_selector "#token-form"
    assert_equal ["/repos/o/r/actions/runs/11"], fake.requests.map(&:path)
  end

  private

  attr_reader :fake

  def page = @session

  def review(entries: nil, files: nil)
    entries ||= [
      {name: "homepage", status: "changed", path: HOMEPAGE, file: "linux/homepage.png"},
      {name: "signup", status: "new", path: SIGNUP, file: "linux/signup.png"}
    ]
    files ||= {"linux/homepage.png" => @homepage_png, "linux/signup.png" => @signup_png}
    zip = FakeGithub.zip({"snap_diff_manifest.json" => JSON.generate(version: 1, entries: entries)}.merge(files))
    @fake = FakeGithub.new(zip: zip)
    yield @fake if block_given?
    # the zip size is read when the fake is built; keep the artifact record honest
    @fake.artifact[:size_in_bytes] = zip.bytesize

    @session = Capybara::Session.new(Capybara.javascript_driver, @fake)
    @session.config.default_max_wait_time = 10
    @session.visit "/?repo=o/r&pr=7&run=11&artifact=22"
    @session.fill_in "token", with: TOKEN
    @session.click_button "Load screenshots"
  end

  def submit
    page.click_button "Submit review"
    page.click_button "Yes, submit"
  end

  def only(requests, verb, path)
    found = requests.select { _1.method == verb && _1.path == path }
    assert_equal 1, found.size, "expected exactly one #{verb} #{path}, saw #{requests.map { "#{_1.method} #{_1.path}" }}"
    found.first
  end
end
