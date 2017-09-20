if defined?(Rake) && (RUBY_ENGINE != 'jruby' || org.jruby.RubyInstanceConfig.FULL_TRACE_ENABLED)
  require 'simplecov'
  SimpleCov.start
  SimpleCov.minimum_coverage RUBY_ENGINE == 'jruby' ? 82.5 : 83.5
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

TEST_IMAGES_DIR = File.expand_path('images', __dir__)

module Rails
  def self.root
    File.expand_path '../tmp', __dir__
  end
end

require 'capybara/screenshot/diff'
require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use!

# TODO(uwe): Remove when we stop support for Rails 4.2
ActiveSupport.test_order = :random
# ODOT

module Capybara
  module Screenshot
    module Diff
      module TestHelper
        private

        def save_screenshot(file_name)
          source_image = File.basename(file_name)
          source_image.slice!(/^\d\d_/)
          FileUtils.cp File.expand_path("images/#{source_image}", __dir__), file_name
        end

        def make_comparison(old_img, new_img, color_distance_limit: nil)
          comp = ImageCompare.new("#{Rails.root}/screenshot.png", color_distance_limit: color_distance_limit)
          set_test_images(comp, old_img, new_img)
          comp
        end

        def set_test_images(comp, old_img, new_img)
          FileUtils.mkdir_p File.dirname(comp.old_file_name)
          FileUtils.cp "#{TEST_IMAGES_DIR}/#{old_img}.png", comp.old_file_name
          FileUtils.cp "#{TEST_IMAGES_DIR}/#{new_img}.png", comp.new_file_name
        end

        def evaluate_script(*)
          # Do nothing
        end
      end
    end
  end
end
