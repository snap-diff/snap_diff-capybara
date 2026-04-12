# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/reporters/html"

module CapybaraScreenshotDiff
  module Reporters
    class HTMLReporterTest < ActiveSupport::TestCase
      setup do
        @output_dir = Pathname.new(Dir.mktmpdir)
        @output_path = @output_dir / "report.html"
      end

      teardown do
        FileUtils.remove_entry(@output_dir)
      end

      test "#format with no assertions writes nothing" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([])

        assert_not @output_path.exist?
      end

      test "#format with passing assertions writes nothing" do
        reporter = HTML.new(output_path: @output_path)

        assertion = build_passing_assertion("index")
        reporter.record([assertion])

        assert_not @output_path.exist?
      end

      test "#record and #finalize with failing assertion generates HTML file" do
        reporter = HTML.new(output_path: @output_path)

        reporter.record([build_failing_assertion("index")])
        reporter.finalize

        assert @output_path.exist?
        html = @output_path.read
        assert_includes html, "<!DOCTYPE html>"
        assert_includes html, "index"
      end

      test "#record and #finalize includes summary stats" do
        reporter = HTML.new(output_path: @output_path)

        reporter.record([
          build_failing_assertion("page_a"),
          build_passing_assertion("page_b"),
          build_failing_assertion("page_c")
        ])
        reporter.finalize

        html = @output_path.read
        assert_match(/Total.*<strong>3<\/strong>/, html)
        assert_match(/Failed.*<strong>2<\/strong>/, html)
        assert_match(/Passed.*<strong>1<\/strong>/, html)
      end

      test "#record tolerates broken assertions without crashing" do
        reporter = HTML.new(output_path: @output_path)

        broken = ScreenshotAssertion.new("broken")
        broken.compare = Object.new # will raise on .difference

        valid = build_failing_assertion("valid")

        assert_nothing_raised do
          reporter.record([broken, valid])
        end

        reporter.finalize
        assert @output_path.exist?
        assert_includes @output_path.read, "valid"
      end

      private

      def build_passing_assertion(name)
        difference_stub = Struct.new(:different?).new(false)
        compare_stub = Struct.new(:difference, :different?).new(difference_stub, false)
        ScreenshotAssertion.new(name).tap { |a| a.compare = compare_stub }
      end

      def build_failing_assertion(name)
        reporter_stub = Struct.new(:annotated_image_path, :annotated_base_image_path, :heatmap_diff_path)
          .new(@output_dir / "#{name}.diff.png", @output_dir / "#{name}.base.diff.png", @output_dir / "#{name}.heatmap.diff.png")

        difference_stub = Struct.new(:different?).new(true)
        compare_stub = Struct.new(:difference, :different?, :base_image_path, :image_path, :reporter)
          .new(difference_stub, true, @output_dir / "#{name}.base.png", @output_dir / "#{name}.png", reporter_stub)

        ScreenshotAssertion.new(name).tap { |a| a.compare = compare_stub }
      end
    end
  end
end
