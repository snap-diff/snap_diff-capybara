# frozen_string_literal: true

require "test_helper"
require "open3"
require "json"
require "tmpdir"

module CapybaraScreenshotDiff
  # Regression test for the "never mask a real failure with a pending
  # marker" guard in capybara_screenshot_diff/rspec.rb's `config.after` hook.
  #
  # This must run the fixture in a genuinely separate process: RSpec's own
  # after-hook exception handling folds a `skip` raised from an after-hook
  # into the example's pending state (it resets `example.exception` because
  # `Pending.mark_skipped!` already flipped `example.pending?` to true before
  # the skip exception is caught). That only reproduces end-to-end via a
  # real `RSpec::Core::Runner.run` exit status + report, not via an
  # in-process assertion on some Ruby object.
  class RspecPendingMaskingTest < ActiveSupport::TestCase
    test "a genuine example failure is never masked as pending by pending_if_new" do
      spec_file = file_fixture("rspec_pending_masking_spec.rb").to_s

      Dir.mktmpdir do |dir|
        json_path = File.join(dir, "result.json")

        script = <<~RUBY
          require "rspec/core"
          exit RSpec::Core::Runner.run([#{spec_file.inspect}, "--format", "json", "--out", #{json_path.inspect}], $stderr, $stdout)
        RUBY

        out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-Itest", "-e", script)

        refute status.success?, "expected the pending-masking fixture to fail the process, got:\n#{out}"

        summary = JSON.parse(File.read(json_path))["summary"]

        assert_equal 1, summary["example_count"], out
        assert_equal 1, summary["failure_count"],
          "expected the deliberate failure to be reported as a failure, not masked:\n#{out}"
        assert_equal 0, summary["pending_count"],
          "expected pending_if_new to NOT mask the failure as pending:\n#{out}"
      end
    end
  end
end
