# frozen_string_literal: true

require "test_helper"
require "open3"

# LEGACY SURFACE (test/legacy/, see the Rakefile): both entry points under
# test are deleted with lib/capybara* in 2.1.
#
# `snap_diff/integrations/minitest` warns when it was activated as a side
# effect of an entry point rather than required on purpose. WHICH entries
# count is the whole question, and it has a false-positive direction and a
# false-negative one -- hence a test for both:
#
#   * lib/capybara-screenshot-diff.rb is the gem-NAME file. `Bundler.require`
#     requires the gem's own name, so it loads for everyone with
#     `gem "capybara-screenshot-diff"` in their Gemfile no matter what they
#     require explicitly. Keying the warning off it shouted at every user on
#     every run with no action available to silence it.
#   * lib/capybara/screenshot/diff.rb is the v1 NAMESPACE entry. Requiring it
#     IS the deprecated choice, and the fix is to change that one line.
class MinitestActivationWarningTest < ActiveSupport::TestCase
  test "the gem-name entry point (what Bundler.require loads) does not warn" do
    assert_equal "", warnings_from(<<~RUBY)
      require "capybara-screenshot-diff"
      require "snap_diff/integrations/minitest"
    RUBY
  end

  test "the v1 namespace entry point still warns" do
    warnings = warnings_from(%(require "capybara/screenshot/diff"))

    assert_match(/\[DEPRECATION\]/, warnings)
    assert_match(%r{snap_diff/integrations/minitest}, warnings,
      "the remedy must name the canonical require, not another deprecated one")
  end

  # It was a bare Kernel#warn, so the documented switch did not reach it --
  # a deprecation you cannot silence is one more thing users learn to ignore.
  test "the warning is silenced by the documented deprecation switch" do
    assert_equal "", warnings_from(%(require "capybara/screenshot/diff"),
      "SNAP_DIFF_SILENCE_DEPRECATIONS" => "1")
  end

  private

  # Runs +script+ in a fresh process with only lib/ on the load path and
  # returns its stderr if the activation warning is in there (the message is
  # multi-line, so grepping for the marker line would drop the remedy), "" if
  # it is not.
  def warnings_from(script, env = {})
    project_root = File.expand_path("../..", __dir__)
    _out, err, status = Open3.capture3(env, RbConfig.ruby, "-Ilib", "-e", script, chdir: project_root)
    assert_predicate status, :success?, err
    err.include?("[DEPRECATION]") ? err : ""
  end
end
