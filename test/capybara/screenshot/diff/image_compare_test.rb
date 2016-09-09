require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        test 'compare class method' do
          assert ImageCompare.compare("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/b.png")
        end

        test 'it can be instantiated' do
          assert ImageCompare.new('images/a.png', 'images/b.png')
        end

        test 'it can be instantiated with dimensions' do
          assert ImageCompare.new('images/a.png', 'images/b.png', [80, 80])
        end

        test 'compare then dimensions and cleanup' do
          comp = ImageCompare.new("#{TEST_IMAGES_DIR}/a.png", "#{TEST_IMAGES_DIR}/c.png")
          assert comp.compare
          assert_equal [11, 3, 48, 20], comp.dimensions
          ImageCompare.compare("#{TEST_IMAGES_DIR}/c.png", "#{TEST_IMAGES_DIR}/c.png")
        end
      end
    end
  end
end
