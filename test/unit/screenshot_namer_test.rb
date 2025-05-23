# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class ScreenshotNamerTest < ActiveSupport::TestCase
    setup do
      @screenshot_area_root = Dir.mktmpdir("screenshots_area")
      @screenshot_namer = ScreenshotNamer.new(@screenshot_area_root)
    end

    teardown do
      FileUtils.remove_entry(@screenshot_area_root) if Dir.exist?(@screenshot_area_root)
    end

    test "#group= adds group to screenshot directory path" do
      @screenshot_namer.group = "group_name"
      assert_includes @screenshot_namer.current_group_directory.to_s, "group_name"
    end

    test "#group= resets counter when group changes" do
      @screenshot_namer.group = "group1"
      assert_equal "group1/00_image", @screenshot_namer.full_name("image")
      assert_equal "group1/01_image", @screenshot_namer.full_name("image")

      @screenshot_namer.group = "group2"
      assert_equal "group2/00_image", @screenshot_namer.full_name("image")
    end

    test "#group= handles nil group" do
      @screenshot_namer.group = nil
      assert_equal "image", @screenshot_namer.full_name("image")
      assert_equal [], @screenshot_namer.directory_parts
    end

    test "#group= handles empty string group" do
      @screenshot_namer.group = ""
      assert_equal "image", @screenshot_namer.full_name("image")
      assert_equal [], @screenshot_namer.directory_parts
    end

    test "#section= sets section for directory path" do
      @screenshot_namer.section = "section_name"
      assert_includes @screenshot_namer.current_group_directory.to_s, "section_name"
    end

    test "#section= handles nil section" do
      @screenshot_namer.section = nil
      assert_equal [], @screenshot_namer.directory_parts
    end

    test "#section= handles empty string section" do
      @screenshot_namer.section = ""
      assert_equal [], @screenshot_namer.directory_parts
    end

    test "#full_name generates basic name when no group is set" do
      assert_equal "image_a", @screenshot_namer.full_name("image_a")
      assert_equal "image_b", @screenshot_namer.full_name("image_b")
    end

    test "#full_name generates prefixed and incremented names when group is set" do
      @screenshot_namer.group = "user_flow"
      assert_equal "user_flow/00_step1", @screenshot_namer.full_name("step1")
      assert_equal "user_flow/01_step2", @screenshot_namer.full_name("step2")
    end

    test "#full_name handles symbol base_name and group" do
      @screenshot_namer.group = "symbols"
      assert_equal "symbols/00_my_symbol", @screenshot_namer.full_name(:my_symbol)
      @screenshot_namer.group = nil
      assert_equal "plain_symbol", @screenshot_namer.full_name(:plain_symbol)
    end

    test "#full_name_with_path includes screenshot_area" do
      expected_path = File.join(@screenshot_area_root, "image_a")
      assert_equal expected_path, @screenshot_namer.full_name_with_path("image_a")
    end

    test "#full_name_with_path handles nil screenshot_area" do
      namer_no_area = @screenshot_namer
      namer_no_area.section = "s"
      namer_no_area.group = "g"
      assert_includes namer_no_area.full_name_with_path("image"), File.join("s", "g", "00_image")
    end

    test "#full_name_with_path includes section when set" do
      @screenshot_namer.section = "checkout"
      expected_path = File.join(@screenshot_area_root, "checkout", "details")
      assert_equal expected_path, @screenshot_namer.full_name_with_path("details")
    end

    test "#full_name_with_path includes group and counter when set" do
      @screenshot_namer.group = "payment"
      expected_path = File.join(@screenshot_area_root, "payment", "00_credit_card")
      assert_equal expected_path, @screenshot_namer.full_name_with_path("credit_card")
      expected_path_next = File.join(@screenshot_area_root, "payment", "01_confirmation")
      assert_equal expected_path_next, @screenshot_namer.full_name_with_path("confirmation")
    end

    test "#full_name_with_path includes section and group" do
      @screenshot_namer.section = "user_profile"
      @screenshot_namer.group = "avatar_upload"
      expected_path = File.join(@screenshot_area_root, "user_profile", "avatar_upload", "00_new_image")
      assert_equal expected_path, @screenshot_namer.full_name_with_path("new_image")
    end

    test "#full_name_with_path adds counter for duplicated names with active group" do
      @screenshot_namer.group = "user_flow"
      assert_equal "user_flow/00_step1", @screenshot_namer.full_name("step1")
      assert_equal "user_flow/01_step1", @screenshot_namer.full_name("step1")
      assert_equal "user_flow/02_step1", @screenshot_namer.full_name("step1")
    end

    test "#full_name_with_path ignores duplicate names without active group" do
      @screenshot_namer.group = nil
      assert_equal "step1", @screenshot_namer.full_name("step1")
      assert_equal "step1", @screenshot_namer.full_name("step1")
    end

    test "#directory_parts is empty initially" do
      assert_equal [], @screenshot_namer.directory_parts
    end

    test "#directory_parts contains section when set" do
      @screenshot_namer.section = "s1"
      assert_equal ["s1"], @screenshot_namer.directory_parts
    end

    test "#directory_parts contains group when set" do
      @screenshot_namer.group = "g1"
      assert_equal ["g1"], @screenshot_namer.directory_parts
    end

    test "#directory_parts contains section and group when both set" do
      @screenshot_namer.section = "s1"
      @screenshot_namer.group = "g1"
      assert_equal ["s1", "g1"], @screenshot_namer.directory_parts
    end

    test "#clear_current_group_directory removes group directory" do
      @screenshot_namer.group = "to_clear"
      dir_path = @screenshot_namer.current_group_directory
      FileUtils.mkdir_p(dir_path)
      assert Dir.exist?(dir_path)

      @screenshot_namer.clear_current_group_directory
      assert_not Dir.exist?(dir_path)
    end

    test "#clear_current_group_directory handles non-existent directories" do
      @screenshot_namer.group = "nonexistent"
      assert_nothing_raised { @screenshot_namer.clear_current_group_directory }
    end

    test "#current_group_directory constructs full directory path" do
      @screenshot_namer.section = "section1"
      @screenshot_namer.group = "group1"
      expected_path = File.join(@screenshot_area_root, "section1", "group1")
      assert_equal expected_path, @screenshot_namer.current_group_directory
    end
  end
end
