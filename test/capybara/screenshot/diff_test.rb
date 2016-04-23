require 'test_helper'

class Capybara::Screenshot::DiffTest < ActionDispatch::IntegrationTest
  def test_that_it_has_a_version_number
    refute_nil ::Capybara::Screenshot::Diff::VERSION
  end

  def test_screenshot_groups_are_appended
    assert_equal nil, @screenshot_group
    screenshot_group 'a'
    assert_equal 'a', @screenshot_group
    screenshot_group 'b'
    assert_equal 'a/b', @screenshot_group
  end
end
