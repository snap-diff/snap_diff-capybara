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
# core preloaded, so such gaps fail in ANY suite run.
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
end
