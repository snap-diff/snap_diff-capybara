# frozen_string_literal: true

require "system_test_case"

# NOTE: For this test we need only chrome browser,
#       because we can spot problem by counting running chrome driver processes
require "action_pack/version"
unless [ActionPack::VERSION::MAJOR, ActionPack::VERSION::MINOR].join >= "60" && ENV["CAPYBARA_DRIVER"].include?("selenium_chrome")
  warn "Regression only for 6x Rails and driven_by construction"
  return
end

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
