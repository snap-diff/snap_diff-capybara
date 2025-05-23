# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/utils"
require "minitest/stub_const"

module Capybara
  module Screenshot
    module Diff
      class UtilsTest < ActiveSupport::TestCase
        test "#detect_available_drivers includes :vips when ruby-vips gem is available" do
          skip "VIPS not present. Skipping VIPS driver tests." unless defined?(Vips)
          Object.stub :require, ->(gem) { gem == "vips" } do
            assert_includes Utils.detect_available_drivers, :vips
          end
        end

        test "#detect_available_drivers excludes :vips when ruby-vips gem is not available" do
          Object.stub_remove_const(:Vips) do
            Object.stub :require, ->(gem) { gem != "vips" } do
              assert_not_includes Utils.detect_available_drivers, :vips
            end
          end
        end

        test "#detect_available_drivers excludes :vips when system libvips is not installed" do
          Object.stub_remove_const(:Vips) do
            Object.stub :require, ->(gem) { gem == "vips" && raise(LoadError.new("Could not ... vips")) } do
              assert_not_includes Utils.detect_available_drivers, :vips
            end
          end
        end

        test "#detect_available_drivers returns drivers in order of preference when multiple are available" do
          Object.stub_consts(Vips: Class.new, ChunkyPNG: Class.new) do
            Object.stub :require, true do
              assert_equal %i[vips chunky_png], Utils.detect_available_drivers
            end
          end
        end

        test "#detect_available_drivers includes :chunky_png when the gem is available" do
          Object.stub :require, ->(gem) { gem == "chunky_png" } do
            assert_includes Utils.detect_available_drivers, :chunky_png
          end
        end

        test "#detect_available_drivers excludes :chunky_png when the gem is not available" do
          Object.stub_remove_const(:ChunkyPNG) do
            Object.stub :require, ->(gem) { gem != "chunky_png" } do
              assert_not_includes Utils.detect_available_drivers, :chunky_png
            end
          end
        end
      end
    end
  end
end
