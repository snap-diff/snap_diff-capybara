# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class VcsTest < ActionDispatch::IntegrationTest
        include Vcs

        setup do
          @base_screenshot = Tempfile.new(%w[vcs_base_screenshot. .attempt.0.png], Screenshot.root)
        end

        teardown do
          if @base_screenshot.is_a?(Tempfile)
            @base_screenshot.close
            @base_screenshot.unlink
          end
        end

        test "checkout of original screenshot" do
          screenshot_path = Screenshot.root / "../test/images/a.png"
          base_screenshot_path = Pathname.new(@base_screenshot.path)
          assert Vcs.restore_git_revision(screenshot_path, base_screenshot_path, root: Screenshot.root)

          assert base_screenshot_path.exist?
          assert_equal screenshot_path.size, base_screenshot_path.size
        end
      end
    end
  end
end
