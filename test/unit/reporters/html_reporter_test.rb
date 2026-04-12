# frozen_string_literal: true

require "test_helper"
require "capybara_screenshot_diff/reporters/html"

module CapybaraScreenshotDiff
  module Reporters
    class HTMLReporterTest < ActiveSupport::TestCase
      include CapybaraScreenshotDiff::DSLStub

      setup do
        @output_dir = Pathname.new(Dir.mktmpdir)
        @output_path = @output_dir / "report.html"
      end

      teardown do
        FileUtils.remove_entry(@output_dir)
      end

      test "#record with no assertions writes nothing" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([])

        assert_not @output_path.exist?
      end

      test "#record with passing assertions writes nothing" do
        reporter = HTML.new(output_path: @output_path)

        reporter.record([build_passing_assertion("index")])
        reporter.finalize

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
        assert_includes html, "2 failed"
        assert_includes html, "1 passed"
        assert_includes html, "3 total"
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

      test "#record uses relative paths by default" do
        reporter = HTML.new(output_path: @output_path)

        reporter.record([build_failing_assertion("rel")])
        reporter.finalize

        html = @output_path.read
        assert_not_includes html, "data:image"
      end

      test "#record embeds base64 images when embed_images: true" do
        reporter = HTML.new(output_path: @output_path, embed_images: true)

        reporter.record([build_failing_assertion("embed")])
        reporter.finalize

        html = @output_path.read
        assert_includes html, "data:image/png;base64,"
      end

      private

      def build_passing_assertion(name)
        compare = make_comparison(:a, :a, destination: "pass_#{name}")
        compare.processed

        ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
      end

      def build_failing_assertion(name)
        compare = make_comparison(:a, :b, destination: "fail_#{name}")
        compare.processed

        ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
      end
    end
  end
end
