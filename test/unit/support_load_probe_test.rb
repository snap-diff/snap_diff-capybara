# frozen_string_literal: true

require "test_helper"
require "open3"

# Kaizen guard for support-file transitive-require gaps (same subprocess
# pattern as snap_diff_test.rb's standalone-load regression test).
#
# test_helper.rb preloads the whole gem, so a support file missing one of its
# own requires still loads fine in most suite runs and only breaks in the CI
# matrix cell with a different load order — exactly how
# setup_capybara_drivers.rb broke on selenium_chrome_headless + vips (it used
# Capybara::Screenshot::Os without requiring it, fixed in b7ada5e). This test
# requires every test/support file in a bare subprocess with only capybara
# core preloaded. Scope: it catches missing requires for constants referenced
# AT LOAD TIME under this process's env; references hidden behind env guards
# (e.g. CAPYBARA_DRIVER branches not taken here) or inside method bodies
# still escape it.
#
# Currently every support file is expected to be bare-loadable: each one
# requires what it uses (rack/action_controller in setup_rails_app,
# active_support/concern in dsl_stub and driver_contract_tests, the gem's own
# files elsewhere). If a future support file legitimately needs more context
# than "capybara is loaded", list it in SKIP with the reason.
class SupportLoadProbeTest < ActiveSupport::TestCase
  SKIP = {
    # "support/example" => "why it cannot load bare"
  }.freeze

  test "every test/support file is requirable with only capybara core loaded" do
    project_root = File.expand_path("../..", __dir__)
    support_files = Dir.chdir(File.join(project_root, "test")) { Dir["support/**/*.rb"] }.sort
    assert_operator support_files.size, :>=, 10, "probe should see the support files"

    failures = support_files.filter_map do |file|
      require_path = file.sub(/\.rb\z/, "")
      next if SKIP.key?(require_path)

      script = "require \"capybara\"; require #{require_path.inspect}"
      out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-Itest", "-e", script, chdir: project_root)

      "#{file}:\n#{out}" unless status.success?
    end

    assert_empty failures, <<~MSG
      Support file(s) rely on requires test_helper happens to load first.
      Add the missing require to the support file itself (or document a SKIP here):

      #{failures.join("\n\n")}
    MSG
  end

  # Alias-completeness probe (the f89cea2 bug class): each documented entry
  # point must define its advertised constants when it is the ONLY require —
  # the acyclic redesign once narrowed capybara_screenshot_diff/minitest so
  # consumers lost CapybaraScreenshotDiff::DSL, and only one CI matrix leg
  # noticed. capybara_screenshot_diff/cucumber is not probed: it calls
  # World(...) at load, which only exists inside cucumber's runtime context.
  ENTRY_POINTS = {
    "capybara_screenshot_diff" => %w[
      CapybaraScreenshotDiff::DSL Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ],
    "capybara_screenshot_diff/minitest" => %w[
      CapybaraScreenshotDiff::DSL CapybaraScreenshotDiff::Minitest::Assertions
      Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ],
    "capybara_screenshot_diff/rspec" => %w[
      CapybaraScreenshotDiff::DSL Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ],
    "capybara-screenshot-diff" => %w[
      CapybaraScreenshotDiff::DSL CapybaraScreenshotDiff::Minitest::Assertions
      Capybara::Screenshot::Os Capybara::Screenshot::Diff
    ]
  }.freeze

  test "every documented entry point defines its advertised constants standalone" do
    project_root = File.expand_path("../..", __dir__)

    failures = ENTRY_POINTS.filter_map do |entry, constants|
      script = <<~RUBY
        require #{entry.inspect}
        missing = #{constants.inspect}.reject { |c| Object.const_defined?(c) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
      out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", script, chdir: project_root)

      "require \"#{entry}\" -> #{out}" unless status.success?
    end

    assert_empty failures, <<~MSG
      Entry point(s) no longer provide their advertised constants standalone:

      #{failures.join("\n")}
    MSG
  end
end
