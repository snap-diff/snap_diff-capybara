if defined?(Rake) && (RUBY_ENGINE != 'jruby' || org.jruby.RubyInstanceConfig.FULL_TRACE_ENABLED)
  require 'simplecov'
  SimpleCov.start
  SimpleCov.minimum_coverage 83
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

TEST_IMAGES_DIR = File.expand_path('images', __dir__)

module Rails
  def self.root
    File.expand_path '../tmp/screenshots', __dir__
  end
end

require 'capybara/screenshot/diff'
require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use!

# TODO(uwe): Remove when we stop support for Rails 4.2
ActiveSupport.test_order = :random
# ODOT

module ActionDispatch
  class IntegrationTest
    def save_screenshot(file_name)
      source_image = File.basename(file_name)
      source_image.slice!(/^\d\d_/)
      FileUtils.cp File.expand_path("images/#{source_image}", __dir__), file_name
    end
  end
end
