# frozen_string_literal: true

require "test_helper"
require "open3"
require "json"
require "tmpdir"

# Regression test for the "gem's pending hook must run after the full user
# after-chain" guard in capybara_screenshot_diff/rspec.rb.
#
# This must run the fixture in a genuinely separate process: RSpec's
# `after(:each)` hooks run in REVERSE registration order, so a
# `config.after` hook registered BEFORE `capybara_screenshot_diff/rspec`
# is required runs AFTER the gem's own `config.after` hook. If the gem's
# hook isn't guaranteed to run last, it commits to "pending" before the
# user's hook has had a chance to raise, and that later raise gets folded
# into `pending_exception` (via `Example#set_exception`) rather than
# `example.exception`, silently masking the real failure. That only
# reproduces end-to-end via a real `RSpec::Core::Runner.run` exit status +
# report, not via an in-process assertion on some Ruby object.
class RspecAfterHookOrderMaskingTest < ActiveSupport::TestCase
  test "a real failure from an after hook registered before the gem loaded is never masked as pending" do
    spec_file = file_fixture("rspec_after_hook_order_masking_spec.rb").to_s

    Dir.mktmpdir do |dir|
      json_path = File.join(dir, "result.json")

      script = <<~RUBY
        require "rspec/core"
        exit RSpec::Core::Runner.run([#{spec_file.inspect}, "--format", "json", "--out", #{json_path.inspect}], $stderr, $stdout)
      RUBY

      out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-Itest", "-e", script)

      refute status.success?, "expected the after-hook-order-masking fixture to fail the process, got:\n#{out}"

      summary = JSON.parse(File.read(json_path))["summary"]

      assert_equal 1, summary["example_count"], out
      assert_equal 1, summary["failure_count"],
        "expected the after hook's real failure to be reported as a failure, not masked:\n#{out}"
      assert_equal 0, summary["pending_count"],
        "expected pending_if_new to NOT mask the after hook's failure as pending:\n#{out}"
    end
  end
end
