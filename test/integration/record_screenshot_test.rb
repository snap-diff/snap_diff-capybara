# frozen_string_literal: true

require "system_test_case"

class RecordScreenshotTest < SystemTestCase
  setup do
    screenshot_section class_name.underscore.sub(/(_feature|_system)?_test$/, "") unless CapybaraScreenshotDiff.screenshot_namer.section
    screenshot_group name[5..] unless CapybaraScreenshotDiff.screenshot_namer.group

    @original_tolerance = Capybara::Screenshot::Diff.tolerance
    Capybara::Screenshot::Diff.tolerance = (Capybara::Screenshot::Diff.driver == :vips) ? 0.035 : 0.7
  end

  teardown do
    Capybara::Screenshot.blur_active_element = nil
    Capybara::Screenshot::Diff.tolerance = @original_tolerance
  end

  def test_record_index
    visit "/"

    screenshot "index"
  end

  def test_record_index_cropped
    visit "/"

    screenshot "index-cropped", crop: "form"
  end

  def test_record_index_as_webp
    skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)

    visit "/"

    screenshot "index-vips", screenshot_format: "webp", driver: :vips
  end

  def test_record_index_with_stability
    visit "/"

    screenshot "index", stability_time_limit: 0.1, wait: (RUBY_ENGINE == "jruby") ? 10 : 1
  end
end
