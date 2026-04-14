# frozen_string_literal: true

require "test_helper"

module Capybara
  module Screenshot
    module Diff
      class VcsTest < ActiveSupport::TestCase
        include Vcs

        PROJECT_ROOT = Pathname.new(File.expand_path("../..", __dir__))

        setup do
          @tmp_dir = PROJECT_ROOT / "tmp" / "vcs_test_#{Process.pid}"
          FileUtils.mkdir_p(@tmp_dir)
          @base_screenshot = Tempfile.new(%w[vcs_base. .png], @tmp_dir.to_s)
        end

        teardown do
          @base_screenshot&.close
          @base_screenshot&.unlink
          FileUtils.rm_rf(@tmp_dir)
        end

        test "#checkout_vcs checks out and verifies the original screenshot" do
          screenshot_path = file_fixture("images/a.png")
          base_screenshot_path = Pathname.new(@base_screenshot.path)

          assert Vcs.checkout_vcs(@tmp_dir, screenshot_path, base_screenshot_path),
            "checkout_vcs failed: root=#{@tmp_dir}"

          assert base_screenshot_path.exist?
          assert_equal screenshot_path.size, base_screenshot_path.size
        end

        test "#checkout_vcs ignores external git env overrides" do
          screenshot_path = file_fixture("images/a.png")
          base_screenshot_path = Pathname.new(@base_screenshot.path)

          with_env("GIT_DIR" => "/tmp/does-not-exist", "GIT_WORK_TREE" => "/tmp/does-not-exist") do
            assert Vcs.checkout_vcs(@tmp_dir, screenshot_path, base_screenshot_path),
              "checkout_vcs failed with overridden git env: root=#{@tmp_dir}"
          end

          assert base_screenshot_path.exist?
          assert_equal screenshot_path.size, base_screenshot_path.size
        end

        private

        def with_env(vars)
          previous = vars.transform_values { |_, _| nil }
          vars.each_key { |key| previous[key] = ENV[key] }
          vars.each { |key, value| ENV[key] = value }
          yield
        ensure
          previous.each { |key, value| ENV[key] = value }
        end
      end
    end
  end
end
