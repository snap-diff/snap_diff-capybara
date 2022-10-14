# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
  SimpleCov.minimum_coverage 91
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

TEST_IMAGES_DIR = File.expand_path("images", __dir__)

# NOTE: Simulate Rails Environment
module Rails
  def self.root
    Pathname("../tmp").expand_path(__dir__)
  end

  def self.application
    Rack::Builder.new {
      use(Rack::Static, urls: [""], root: "test/fixtures/app", index: "index.html")
      run ->(_env) { [200, {}, []] }
    }.to_app
  end
end

require "capybara/screenshot/diff"
require "minitest/autorun"
require "capybara/minitest"

require "capybara/dsl"
Capybara.disable_animation = true
# FIXME: Uncomment when capybara will support puma 6
# Capybara.server = :puma, {Silent: true}
Capybara.threadsafe = true
Capybara.app = Rails.application

module Capybara
  module Screenshot
    module Diff
      module TestHelper
        private

        # Stub of Capybara's checkout_vcs
        def checkout_vcs(name, old_file_name, new_file_name)
          # Do nothing
        end

        # Stub of the Capybara's save_screenshot
        def save_screenshot(file_name)
          source_image = File.basename(file_name)
          source_image.slice!(/^\d\d_/)
          FileUtils.cp File.expand_path("images/#{source_image}", __dir__), file_name
        end

        def make_comparison(old_img, new_img, name: "screenshot", **options)
          comp = ImageCompare.new("#{Rails.root}/doc/screenshots/#{name}.png", nil, **options)
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
