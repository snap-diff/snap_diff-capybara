# frozen_string_literal: true

require "test_helper"
require "snap_diff"

module SnapDiff
  # The failure message names the line of the user's code that took the
  # screenshot, once, instead of the whole call stack. Frames are built
  # from real files, because a frame only counts as user code when its
  # file exists.
  class ScreenshotAssertionCallSiteTest < ActiveSupport::TestCase
    include SnapDiff::DSL
    include DSLStub

    def setup
      super
      @comparison = make_comparison(:a, :b)
    end

    test "names the first frame outside the gem, installed gems and Ruby's library" do
      user_frame = "#{__FILE__}:#{__LINE__}:in 'block in <class:ScreenshotAssertionCallSiteTest>'"
      frames = [
        "#{Gem.loaded_specs.fetch("rspec-expectations").full_gem_path}/lib/rspec/matchers/dsl.rb:535:in 'method_missing'",
        "#{BacktraceFilter::LIB_DIRECTORY}snap_diff/integrations/rspec.rb:24:in 'block (2 levels) in <top (required)>'",
        "#{Dir[File.join(RbConfig::CONFIG["rubylibdir"], "*.rb")].first}:1:in 'require'",
        "<internal:kernel>:91:in 'tap'",
        "(eval at #{__FILE__}:1):1:in 'block'",
        user_frame,
        "#{__FILE__}:1:in 'later frame'"
      ]

      SnapDiff.config.stub(:root, Pathname(Dir.pwd)) do
        assert_equal "test/unit/screenshot_assertion_call_site_test.rb:#{user_frame[/:(\d+):/, 1]}", call_site_line(frames)
      end
    end

    test "shows a user file outside the root as an absolute path" do
      Dir.mktmpdir do |dir|
        file = File.join(dir, "outside_spec.rb").tap { |f| File.write(f, "") }

        assert_equal "#{file}:7", call_site_line(["#{file}:7:in 'block'"])
      end
    end

    test "matches library roots on directory boundaries" do
      Dir.mktmpdir do |dir|
        library = File.join(dir, "foo", "lib.rb")
        user = File.join(dir, "foobar", "user_spec.rb")
        [library, user].each { |f| FileUtils.mkdir_p(File.dirname(f)) && File.write(f, "") }

        Gem.stub(:path, [File.join(dir, "foo")]) do
          assert_equal "#{user}:3", call_site_line(["#{library}:1:in 'x'", "#{user}:3:in 'y'"])
        end
      end
    end

    test "names a wrapper helper that does not skip its own frame" do
      helper = "#{__FILE__}:10:in 'screenshot'"

      assert_equal "#{__FILE__}:10", call_site_line([helper, "#{__FILE__}:20:in 'test_page'"])
    end

    test "falls back to the first frame when no frame is user code" do
      assert_equal "my_test.rb:42", call_site_line(["my_test.rb:42"])
      assert_equal "<internal:kernel>:91", call_site_line(["<internal:kernel>:91:in 'tap'"])
    end

    test "adds no line when there is no caller" do
      [nil, []].each do |frames|
        message = build_assertion(frames).validate

        assert_equal "Screenshot does not match for 'name': #{@comparison.error_message}", message
      end
    end

    test "each DSL entry point names the test's own line" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        first_line = __LINE__ + 1
        screenshot(create_snapshot_for(:a, :c).full_name)
        assert_matches_screenshot(create_snapshot_for(:a, :c).full_name)
        assert_no_screenshot_changes(create_snapshot_for(:a, :c).full_name)

        assert_equal (first_line..first_line + 2).map { |line| "#{__FILE__}:#{line}" },
          SnapDiff.session.assertions.map { |assertion| assertion.validate.lines.last }
      end
    end

    test "a screenshot checked immediately names the test's own line" do
      SnapDiff::Vcs.stub(:checkout_vcs, true) do
        line = __LINE__ + 2
        error = assert_raises(SnapDiff::ExpectationNotMet) do
          screenshot(create_snapshot_for(:a, :c).full_name, delayed: false)
        end

        assert_equal "#{__FILE__}:#{line}", error.message.lines.last
      end
    end

    private

    def call_site_line(frames)
      build_assertion(frames).validate.lines.last
    end

    def build_assertion(frames)
      SnapDiff::ScreenshotAssertion.new("name").tap do |assertion|
        assertion.compare = @comparison
        assertion.caller = frames
      end
    end
  end
end
