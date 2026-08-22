# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/error_with_filtered_backtrace"

module CapybaraScreenshotDiff
  class BacktraceFilterTest < ActiveSupport::TestCase
    test "#filtered removes lines originating from the given lib directory" do
      filter = BacktraceFilter.new("/app/lib/")

      result = filter.filtered([
        "/app/lib/capybara_screenshot_diff/foo.rb:1:in 'bar'",
        "/app/test/some_test.rb:5:in 'test_thing'"
      ])

      assert_equal ["/app/test/some_test.rb:5:in 'test_thing'"], result
    end

    test "#filtered removes lines from activesupport, minitest, and railties gems" do
      filter = BacktraceFilter.new("/app/lib/")

      result = filter.filtered([
        "/gems/activesupport-7.0.0/lib/foo.rb:1:in 'bar'",
        "/gems/minitest-5.0.0/lib/minitest.rb:2:in 'run'",
        "/gems/railties-7.0.0/lib/baz.rb:3:in 'call'",
        "/app/test/some_test.rb:5:in 'test_thing'"
      ])

      assert_equal ["/app/test/some_test.rb:5:in 'test_thing'"], result
    end

    test "#filtered keeps lines outside the lib directory and unrelated gems" do
      filter = BacktraceFilter.new("/app/lib/")
      backtrace = [
        "/app/test/some_test.rb:5:in 'test_thing'",
        "/gems/rack-3.0.0/lib/rack.rb:1:in 'call'"
      ]

      assert_equal backtrace, filter.filtered(backtrace)
    end

    test "#filtered does not treat a sibling directory sharing the prefix as inside lib" do
      filter = BacktraceFilter.new("/app/lib")

      backtrace = ["/app/library/foo.rb:1:in 'bar'"]

      assert_equal backtrace, filter.filtered(backtrace)
    end

    test "#initialize defaults to the library's own lib directory" do
      filter = BacktraceFilter.new
      lib_file = File.expand_path("../../lib/capybara_screenshot_diff/error_with_filtered_backtrace.rb", __dir__)

      result = filter.filtered([
        "#{lib_file}:1:in 'filtered'",
        "/app/test/some_test.rb:5:in 'test_thing'"
      ])

      assert_equal ["/app/test/some_test.rb:5:in 'test_thing'"], result
    end
  end
end
