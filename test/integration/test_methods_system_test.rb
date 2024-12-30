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

module Capybara
  module Screenshot
    module Diff
      class TestMethodsSystemTest < ActionDispatch::SystemTestCase
        include TestMethods
        include TestMethodsStub

        driven_by :selenium, using: :headless_chrome

        def test_current_capybara_driver_class_do_not_spawn_new_process_when_we_use_system_test_cases
          # NOTE: There is possible that we have several drivers usage in the one suite,
          #       so each of them will have separate instance
          other_activated_drivers = ObjectSpace.each_object(Capybara::Selenium::Driver).count

          3.times { BrowserHelpers.current_capybara_driver_class }

          run_chrome_drivers = ObjectSpace.each_object(Capybara::Selenium::Driver).count
          assert run_chrome_drivers.positive?
          assert run_chrome_drivers - other_activated_drivers <= 1
        end
      end
    end
  end
end
