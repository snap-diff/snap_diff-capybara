# frozen_string_literal: true

require "test_helper"
require "open3"

# Runs a browser-free RSpec fixture in a subprocess, through the real
# `screenshot` and `match_screenshot` entry points, and reads what RSpec
# prints for the failed screenshots.
class RspecCallSiteTest < ActiveSupport::TestCase
  SPEC_FILE = File.expand_path("../fixtures/rspec_call_site_spec.rb", __dir__)

  test "each failed screenshot names its own line of the spec, and nothing else of the stack" do
    out = run_fixture

    %w[screenshot match_screenshot].each do |entry_point|
      line = File.readlines(SPEC_FILE).index { |l| l.include?("# call site: #{entry_point}") } + 1
      assert_equal 1, out.scan(/^ *#{Regexp.escape("#{SPEC_FILE}:#{line}")}$/).size,
        "expected the #{entry_point} call site on its own line, once:\n#{out}"
    end
    refute_match %r{/gems/rspec-}, out, "no rspec frame belongs in the message"
    refute_match %r{lib/snap_diff/}, out, "no snap_diff frame belongs in the message"
  end

  private

  def run_fixture
    script = <<~RUBY
      require "rspec/core"
      exit RSpec::Core::Runner.run([#{SPEC_FILE.inspect}], $stderr, $stdout)
    RUBY
    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-Itest", "-e", script)
    refute status.success?, "expected the fixture's screenshots to fail:\n#{out}"
    out
  end
end
