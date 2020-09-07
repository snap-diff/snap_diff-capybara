# frozen_string_literal: true

require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        include TestHelper

        test 'it can be instantiated with chunky_png driver' do
          comparison = ImageCompare.new('images/b.png')
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test 'it can be instantiated with explicit chunky_png adapter' do
          comparison = ImageCompare.new('images/b.png', driver: :chunky_png)
          assert_kind_of Drivers::ChunkyPNGDriver, comparison.driver
        end

        test 'it can be instantiated with vips adapter' do
          comparison = ImageCompare.new('images/b.png', driver: :vips)
          assert_kind_of Drivers::VipsDriver, comparison.driver
        end

        test 'it can be instantiated with vips adapter and tolerance option' do
          comp = make_comparison(:a, :b, driver: :vips, tolerance: 0.02)
          assert comp.quick_equal?
          assert_not comp.different?
        end

        test 'could pass use tolerance for chunky_png driver' do
          ImageCompare.new('images/b.png', driver: :chunky_png, tolerance: 0.02)
        end

        test 'it can be instantiated with dimensions' do
          assert ImageCompare.new('images/b.png', dimensions: [80, 80])
        end
      end
    end
  end
end
