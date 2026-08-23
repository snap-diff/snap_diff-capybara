# frozen_string_literal: true

require "test_helper"
require "snap_diff/static"

class StaticTest < ActiveSupport::TestCase
  setup do
    @original_root = SnapDiff.config.root
  end

  teardown do
    Capybara.app = Rails.application
    SnapDiff.config.root = @original_root
  end

  test ".serve sets Capybara.app to serve the directory" do
    SnapDiff.serve("test/fixtures")

    assert_kind_of Rack::Files, Capybara.app
  end

  test ".serve sets Screenshot.root to pwd" do
    SnapDiff.serve("test/fixtures")

    assert_equal Pathname(Dir.pwd), SnapDiff.config.root
  end

  # The legacy CapybaraScreenshotDiff.serve forwarder over this is pinned in
  # test/legacy/legacy_forwarders_test.rb.
  test ".serve accepts custom root" do
    SnapDiff.serve("test/fixtures", root: "/tmp")

    assert_equal Pathname("/tmp"), SnapDiff.config.root
  end
end
