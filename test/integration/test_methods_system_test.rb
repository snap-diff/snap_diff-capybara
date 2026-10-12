# frozen_string_literal: true

# NOTE: For this test we need only chrome browser,
#       because we can spot problem by counting running chrome driver processes
unless ENV["CAPYBARA_DRIVER"].include?("selenium_chrome")
  return
end
warn "Regression test for `driven_by :selenium_chrome` construction."

require "system_test_case"
require "action_pack/version"
require "objspace"

class TestMethodsSystemTest < ActionDispatch::SystemTestCase
  include SnapDiff::DSL
  include DSLStub

  # Docker (bin/dtest) has no user namespaces for Chrome's sandbox.
  driven_by(:selenium, using: :headless_chrome) { |options| options.add_argument("--no-sandbox") }

  # Rails resets the sessions after a system test but leaves this :selenium
  # driver current, so every later non-system test would open Chrome with it.
  def after_teardown
    super
  ensure
    Capybara.use_default_driver
  end

  def test_current_capybara_driver_class_do_not_spawn_new_process_when_we_use_system_test_cases
    # NOTE: There is possible that we have several drivers usage in the one suite,
    #       so each of them will have separate instance
    other_activated_drivers = ObjectSpace.each_object(Capybara::Selenium::Driver).count

    3.times { SnapDiff::BrowserHelpers.current_capybara_driver_class }

    run_chrome_drivers = ObjectSpace.each_object(Capybara::Selenium::Driver).count
    assert run_chrome_drivers.positive?
    assert run_chrome_drivers - other_activated_drivers <= 1
  end
end
