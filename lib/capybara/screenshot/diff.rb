require 'capybara/screenshot/diff/version'
require 'capybara/screenshot/diff/image_compare'
require 'capybara/screenshot/diff/capybara_setup'

module Capybara
  module Screenshot
    mattr_accessor :enabled
    mattr_accessor :window_size
    mattr_accessor :add_driver_path
    mattr_accessor :add_os_path

    # Module to track screen shot changes
    module Diff
      mattr_accessor :enabled
      self.enabled = true
    end
  end
end
