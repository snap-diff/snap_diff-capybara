$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'capybara/screenshot/diff'

require 'minitest/autorun'

require 'minitest/reporters'
Minitest::Reporters.use!
