# frozen_string_literal: true

require "test_helper"
require "capybara/screenshot/diff/drivers/utils"
require "minitest/stub_const"

module Capybara
  module Screenshot
    module Diff
      class UtilsTest < ActiveSupport::TestCase
        test "detect_available_drivers add vips when ruby-vips is available" do
          Object.stub :require, ->(gem) { gem == "vips" } do
            assert_includes Utils.detect_available_drivers, :vips
          end
        end

        test "detect_available_drivers does not add :vips when ruby-vips is unavailable" do
          Object.stub_remove_const(:Vips) do
            Object.stub :require, ->(gem) { gem != "vips" } do
              assert_not_includes Utils.detect_available_drivers, :vips
            end
          end
        end

        test "detect_available_drivers does not add :vips when there is no system libvips installed" do
          Object.stub_remove_const(:Vips) do
            Object.stub :require, ->(gem) { gem == "vips" && raise(LoadError.new("Could not ... vips")) } do
              assert_not_includes Utils.detect_available_drivers, :vips
            end
          end
        end

        test "detect_available_drivers returns vips before chunky_png if both gems are available" do
          Object.stub_consts(Vips: Class.new, ChunkyPNG: Class.new) do
            Object.stub :require, true do
              assert_equal %i[vips chunky_png], Utils.detect_available_drivers
            end
          end
        end

        test "detect_available_drivers add chunky_png when chunky_png is available" do
          Object.stub :require, ->(gem) { gem == "chunky_png" } do
            assert_includes Utils.detect_available_drivers, :chunky_png
          end
        end

        test "detect_available_drivers does not add chunky_png when chunky_png is not available" do
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
