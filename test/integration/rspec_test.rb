# frozen_string_literal: true

require "system_test_case"

module CapybaraScreenshotDiff
  class RspecTest < SystemTestCase
    test "RSpec integration runs successfully with capybara-screenshot-diff" do
      # Ensure that the RSpec module is loaded
      require "rspec/core"

      # Run the RSpec spec file
      capture_output = StringIO.new
      spec_file = file_fixture("rspec_spec.rb").to_s
      rspec_status = RSpec::Core::Runner.run([spec_file], capture_output, capture_output)

      assert_equal 0, rspec_status, "RSpec tests failed:\n#{capture_output.string}"
    end
  end
end
