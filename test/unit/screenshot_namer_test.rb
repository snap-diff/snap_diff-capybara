# frozen_string_literal: true

require "test_helper"

module CapybaraScreenshotDiff
  class ScreenshotNamerTest < ActiveSupport::TestCase
    setup do
      @screenshot_namer = SnapDiff::ScreenshotNamer.new
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

    test "#full_name includes section and group" do
      @screenshot_namer.section = "user_profile"
      @screenshot_namer.group = "avatar_upload"
      assert_equal File.join("user_profile", "avatar_upload", "00_new_image"), @screenshot_namer.full_name("new_image")
    end

    test "#full_name adds counter for duplicated names with active group" do
      @screenshot_namer.group = "user_flow"
      assert_equal "user_flow/00_step1", @screenshot_namer.full_name("step1")
      assert_equal "user_flow/01_step1", @screenshot_namer.full_name("step1")
      assert_equal "user_flow/02_step1", @screenshot_namer.full_name("step1")
    end

    test "#full_name ignores duplicate names without active group" do
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
  end
end
