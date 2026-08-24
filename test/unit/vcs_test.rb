# frozen_string_literal: true

require "test_helper"

class VcsTest < ActiveSupport::TestCase
  include SnapDiff::Vcs

  PROJECT_ROOT = Pathname.new(File.expand_path("../..", __dir__))

  setup do
    @tmp_dir = PROJECT_ROOT / "tmp" / "vcs_test_#{Process.pid}"
    FileUtils.mkdir_p(@tmp_dir)
    @base_screenshot = Tempfile.new(%w[vcs_base. .png], @tmp_dir.to_s)
  end

  teardown do
    @base_screenshot&.close
    @base_screenshot&.unlink
    FileUtils.rm_rf(@tmp_dir)
  end

  test "#checkout_vcs checks out and verifies the original screenshot" do
    screenshot_path = file_fixture("images/a.png")
    base_screenshot_path = Pathname.new(@base_screenshot.path)

    assert SnapDiff::Vcs.checkout_vcs(@tmp_dir, screenshot_path, base_screenshot_path),
      "checkout_vcs failed: root=#{@tmp_dir}"

    assert base_screenshot_path.exist?
    assert_equal screenshot_path.size, base_screenshot_path.size
  end

  # `git rev-parse --show-toplevel` is a process spawn (~6ms). It used to run
  # once per screenshot; a 200-screenshot suite spawned it 200 times to get the
  # same answer. A fresh root is used so this test cannot be satisfied by an
  # entry another test left in the cache.
  test "#checkout_vcs asks git for the repository root once per root, not once per screenshot" do
    root = @tmp_dir / "root_#{Time.now.nsec}"
    FileUtils.mkdir_p(root)
    screenshot_path = file_fixture("images/a.png")
    base_screenshot_path = Pathname.new(@base_screenshot.path)

    calls = 0
    status = Object.new
    def status.success? = true
    counting_rev_parse = ->(*) {
      calls += 1
      ["#{PROJECT_ROOT}\n", "", status]
    }

    Open3.stub(:capture3, counting_rev_parse) do
      3.times { SnapDiff::Vcs.checkout_vcs(root, screenshot_path, base_screenshot_path) }
    end

    assert_equal 1, calls
  end

  # A git hook (pre-push, pre-commit) exports GIT_DIR, and GIT_DIR OVERRIDES
  # `-C`. So `git -C <root> show HEAD:<path>` silently reads the wrong
  # repository, the baseline lookup fails, and -- because fail_if_new defaults
  # to false locally -- the screenshot is recorded as new and the test PASSES.
  # Verified by hand: `GIT_DIR=<other> git -C <repo> show HEAD:f.txt` =>
  # "fatal: path 'f.txt' exists on disk, but not in 'HEAD'".
  test "#checkout_vcs ignores an inherited GIT_DIR and honours its own root" do
    screenshot_path = file_fixture("images/a.png")
    base_screenshot_path = Pathname.new(@base_screenshot.path)
    elsewhere = @tmp_dir / "unrelated_repo_#{Time.now.nsec}"
    FileUtils.mkdir_p(elsewhere)
    Open3.capture3("git", "-C", elsewhere.to_s, "init", "--quiet")

    with_env("GIT_DIR" => (elsewhere / ".git").to_s) do
      SnapDiff::Vcs.checkout_vcs(PROJECT_ROOT, screenshot_path, base_screenshot_path)
    end

    assert base_screenshot_path.exist?, "an inherited GIT_DIR must not redirect the baseline lookup"
    assert_equal screenshot_path.size, base_screenshot_path.size
  end

  def with_env(vars)
    previous = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end

  # Concurrent callers must share the cached answer, not each spawn their own
  # git. MRI releases the GVL for the duration of `Open3.capture3`, so without
  # synchronization every thread misses `key?` before any thread writes --
  # measured 8 spawns for 8 threads asking about ONE root, i.e. the cache
  # bought nothing in exactly the mode (`parallelize(with: :threads)`) that is
  # JRuby's default. On JRuby there is no GVL at all, so the unsynchronized
  # Hash write is unsafe as well as wasteful.
  test "#checkout_vcs shares one git lookup across concurrent callers" do
    root = @tmp_dir / "concurrent_root_#{Time.now.nsec}"
    FileUtils.mkdir_p(root)
    screenshot_path = file_fixture("images/a.png")
    base_screenshot_path = Pathname.new(@base_screenshot.path)

    calls = 0
    counter_lock = Mutex.new
    status = Object.new
    def status.success? = true
    counting_rev_parse = ->(*) {
      counter_lock.synchronize { calls += 1 }
      sleep 0.01 # stand in for the real subprocess, which releases the GVL
      ["#{PROJECT_ROOT}\n", "", status]
    }

    Open3.stub(:capture3, counting_rev_parse) do
      8.times.map {
        Thread.new { SnapDiff::Vcs.checkout_vcs(root, screenshot_path, base_screenshot_path) }
      }.each(&:join)
    end

    assert_equal 1, calls, "concurrent callers must share one git lookup, not spawn one each"
  end
end
