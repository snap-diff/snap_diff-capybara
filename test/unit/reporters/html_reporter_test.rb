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

      test "HTML reporter defaults to screenshot root path" do
        reporter = HTML.new
        expected = Capybara::Screenshot.root / Capybara::Screenshot.save_path / "snap_diff_report.html"
        assert_equal expected, reporter.output_path
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

      test "#record from multiple threads produces correct totals" do
        reporter = HTML.new(output_path: @output_path)
        threads = 10
        assertions_per_thread = 5

        workers = threads.times.map do
          Thread.new do
            batch = assertions_per_thread.times.map { |i| build_passing_assertion("t#{Thread.current.object_id}_#{i}") }
            reporter.record(batch)
          end
        end
        workers.each(&:join)

        assert_equal threads * assertions_per_thread, reporter.total
      end

      test "#record and #finalize synchronize internal state" do
        reporter = HTML.new(output_path: @output_path)

        fake_mutex = Class.new do
          attr_reader :synchronize_calls

          def initialize
            @synchronize_calls = 0
          end

          def synchronize
            @synchronize_calls += 1
            yield
          end
        end.new

        # Using private state and a fake mutex here is intentional.
        # This test guards a tricky synchronization detail; avoid refactors unless behavior changes.
        reporter.instance_variable_set(:@mutex, fake_mutex)

        reporter.record([build_passing_assertion("sync")])
        reporter.finalize

        assert_operator fake_mutex.synchronize_calls, :>=, 1
      end

      test "#finalize returns output_path when there are failures" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([build_failing_assertion("fail")])
        result = reporter.finalize

        assert_instance_of Pathname, result
      end

      test "#finalize returns nil when no failures" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([build_passing_assertion("pass")])
        result = reporter.finalize

        assert_nil result
      end

      test "#summary returns screenshot count and status" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([build_passing_assertion("ok"), build_failing_assertion("fail")])
        reporter.finalize

        summary = reporter.summary
        assert_includes summary, "1 failure"
        assert_includes summary, "2 screenshots"
        assert_includes summary, @output_path.to_s
      end

      test "#summary pluralizes failures label for multiple failures" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([
          build_failing_assertion("first failure"),
          build_failing_assertion("second failure")
        ])
        reporter.finalize

        summary = reporter.summary
        assert_includes summary, "2 failures"
        assert_includes summary, "2 screenshots"
        assert_includes summary, @output_path.to_s
      end

      test "#summary when all pass shows no failures" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([build_passing_assertion("ok")])
        reporter.finalize

        summary = reporter.summary
        assert_includes summary, "1 screenshot"
        assert_includes summary, "no failures"
        refute_includes summary, @output_path.to_s
      end

      test "#summary when no screenshots recorded" do
        reporter = HTML.new(output_path: @output_path)
        assert_nil reporter.summary
      end

      test "#finalize can retry after write_report failure" do
        reporter = HTML.new(output_path: @output_path)
        reporter.record([build_failing_assertion("retry")])

        # Make write_report fail on first attempt
        FileUtils.rm_rf(@output_dir)
        File.write(@output_dir.to_s, "not a directory")

        begin
          reporter.finalize
        rescue # rubocop:disable Lint/SuppressedException
        end

        # Restore writable directory and retry
        File.delete(@output_dir.to_s)
        FileUtils.mkdir_p(@output_dir)

        result = reporter.finalize
        assert_instance_of Pathname, result
        assert @output_path.exist?
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
