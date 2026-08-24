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
end
