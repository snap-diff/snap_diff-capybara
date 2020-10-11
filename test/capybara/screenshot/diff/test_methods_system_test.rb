# frozen_string_literal: true

require "action_pack/version"

if [ActionPack::VERSION::MAJOR, ActionPack::VERSION::MINOR].join > "60"
  require "test_helper"
  require "webdrivers/chromedriver"

  Webdrivers::Chromedriver.update

  module Capybara
    module Screenshot
      module Diff
        class TestMethodsSystemTest < ActionDispatch::SystemTestCase
          driven_by :selenium, using: :headless_chrome

          teardown { Capybara.use_default_driver }

          include TestMethods
          include TestHelper

          def test_current_capybara_driver_class_do_not_spawn_new_process
            5.times { current_capybara_driver_class }
            assert_equal 1, `ps x -o pid= -o command=`.scan("webdrivers/chromedriver").size
          end
        end
      end
    end
  end
end
