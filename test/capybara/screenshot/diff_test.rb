require 'test_helper'

class Capybara::Screenshot::DiffTest < ActionDispatch::IntegrationTest
  setup do
    Capybara::Screenshot.add_os_path = true
    Capybara::Screenshot.add_driver_path = true
    Capybara::Screenshot.window_size = [80, 80]
  end

  def test_that_it_has_a_version_number
    refute_nil ::Capybara::Screenshot::Diff::VERSION
  end

  def test_screenshot_groups_are_replaced
    assert_equal nil, @screenshot_group
    screenshot_group 'a'
    assert_equal 'a', @screenshot_group
    screenshot_group 'b'
    assert_equal 'b', @screenshot_group
  end

  def test_screenshot_section_is_prepended
    assert_equal nil, @screenshot_section
    assert_equal nil, @screenshot_group
    screenshot_section 'a'
    assert_equal 'a', @screenshot_section
    assert_equal 'doc/screenshots/rack_test/macos/a', screenshot_dir
    screenshot_group 'b'
    assert_equal 'b', @screenshot_group
    assert_equal 'doc/screenshots/rack_test/macos/a/b', screenshot_dir
    screenshot_group 'c'
    assert_equal 'c', @screenshot_group
    assert_equal 'doc/screenshots/rack_test/macos/a/c', screenshot_dir
  end

  test 'screenshot' do
    screenshot_group 'screenshot'
    screenshot 'a'
  end
end
