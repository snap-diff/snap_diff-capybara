require 'test_helper'

module Capybara
  module Screenshot
    module Diff
      class ImageCompareTest < ActionDispatch::IntegrationTest
        test 'it can be instantiated' do
          assert ImageCompare.new('images/a.png', 'images/b.png')
        end

        test 'it can be instantiated with dimensions' do
          assert ImageCompare.new('images/a.png', 'images/b.png', [80, 80])
        end
      end
    end
  end
end
