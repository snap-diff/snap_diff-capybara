# frozen_string_literal: true

require "system_test_case"

class RecordScreenshotTest < SystemTestCase
  setup do
    screenshot_section class_name.underscore.sub(/(_feature|_system)?_test$/, '') unless @screenshot_section
    screenshot_group name[5..] unless @screenshot_group
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

    screenshot "index", stability_time_limit: 0.1, wait: RUBY_ENGINE == 'jruby' ? 10 : 1
  end
end
