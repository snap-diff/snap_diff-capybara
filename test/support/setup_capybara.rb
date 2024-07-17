# frozen_string_literal: true

require "support/setup_rails_app"

Capybara.app = Rails.application
Capybara.default_max_wait_time = 1
Capybara.disable_animation = true
Capybara.server = :puma, {Silent: true}
Capybara.threadsafe = true
