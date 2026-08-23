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
end
