$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'capybara/screenshot/diff'

require 'minitest/autorun'

require 'minitest/reporters'
Minitest::Reporters.use!

module Rails
  def self.root
    File.expand_path '../tmp/screenshots', __dir__
  end
end

# TODO(uwe): Remove when we stop support for Rails 4.2
ActiveSupport.test_order = :random
# ODOT
