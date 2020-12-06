# frozen_string_literal: true

require "action_pack/version"

ENV["CAPYBARA_DRIVER"] ||= "selenium_chrome_headless"

require "system_test_case"

unless [ActionPack::VERSION::MAJOR, ActionPack::VERSION::MINOR].join >= "60" && ENV["CAPYBARA_DRIVER"].include?("chrome")
  warn "Regression only for 6x Rails and Chrome"
  return
end

module Capybara
  module Screenshot
    module Diff
      class TestMethodsSystemTest < ActionDispatch::SystemTestCase
        driven_by :selenium, using: :headless_chrome

        teardown { Capybara.use_default_driver }

        include TestMethods
        include TestHelper

        def test_current_capybara_driver_class_do_not_spawn_new_process
          2.times { current_capybara_driver_class }
          assert_equal 1, `ps x -o pid= -o command=`.scan("webdrivers/chromedriver").size
        end
      end
    end
  end
end
