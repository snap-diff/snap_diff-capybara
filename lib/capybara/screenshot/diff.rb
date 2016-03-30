require 'capybara/screenshot/diff/version'
require 'capybara/screenshot/diff/image_compare'
require 'capybara/screenshot/diff/capybara_setup'

module Capybara
  module Screenshot
    # Module to track screen shot changes
    module Diff
      mattr_accessor :enabled

      self.enabled = true
    end
  end
end
