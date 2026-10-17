# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require_relative "error_with_filtered_backtrace"
require_relative "screenshot_namer"
require_relative "reporting"

module SnapDiff
  # --- Session lifecycle (per-test) ---
  #
  # The canonical home of the per-test session: the AssertionRegistry
  # holding the assertions and new-screenshot names of the test running
  # here. CapybaraScreenshotDiff.registry / .reset /
  # .pending_screenshots_message are thin forwarders over these.
  #
  # Note: Thread.current[] is *fiber*-local, so a session is per fiber, not
  # per thread. That is pre-existing, documented behaviour (issue #217);
  # ADR-008 step 6 relocates the accessor without touching the semantics.
  def self.session
    Thread.current[:capybara_screenshot_diff_registry] ||= AssertionRegistry.new
  end

  # Ends a test: hands the finished session's assertions to the reporters,
  # then clears it. The one deliberate bridge between the process-global
  # reporter lifecycle (SnapDiff::Reporting) and the per-test session.
  def self.reset
    Reporting.notify(session.assertions)
    session.reset
  end

  # Message to skip the test with when a new screenshot has no baseline yet
  # and `pending_if_new` is enabled. Adapters call this after verifying
  # screenshots, and skip the test with the returned message when present.
  #
  # @return [String, nil] the pending message, or nil when there is nothing to report
  def self.pending_screenshots_message
    return unless SnapDiff.config.pending_if_new && session.new_screenshots_present?

    "No baseline for: #{session.new_screenshots.join(", ")}. Commit the captured screenshots to record them."
  end

  class ScreenshotAssertion
    attr_reader :name, :args
    attr_accessor :compare, :caller

    def initialize(name, **args)
      @name = name
      @args = args
    end

    # One-line debugging summary. Never triggers the (expensive, file-touching)
    # comparison itself: an unprocessed comparison shows as "pending".
    def inspect
      return "#<#{self.class.name} #{name.inspect} (no comparison)>" unless compare

      state = if compare.processed?
        compare.difference.different? ? "different" : "matches"
      else
        "pending"
      end
      "#<#{self.class.name} #{name.inspect} #{state} new=#{compare.image_path} base=#{compare.base_image_path}>"
    end

    # Return an annotated failure message for an unsuppressed screenshot mismatch.
    # Return nil for absent, matching, or suppressed comparisons; archive matching baselines.
    def validate
      return if @validated
      return unless compare

      if compare.different?
        # Optional contribution gate (e.g. AI triage with fail_on:): a
        # registered suppressor runs BEFORE the message is built, so a
        # waived diff never fails and a standing failure can quote what
        # the contributors know. any_suppressor? keeps the no-gate path
        # from even touching compare.difference.
        if Contributions.any_suppressor? && (suppressed = Contributions.suppression_for(name, compare.difference))
          $stdout.puts "[snap_diff:#{suppressed[:source]}] #{name}: failure suppressed -- #{suppressed[:text]}"
          return nil
        end

        # The call site goes last, after what contributors say about the diff.
        notes = Contributions.annotations_for(name).map { |note| "  #{note[:source].upcase} triage: #{note[:text]}" }
        ["Screenshot does not match for '#{name}': #{compare.error_message}", *notes, call_site].compact.join("\n")
      else
        archive_baseline!
        nil
      end
    end

    # Commits the baseline after a passing comparison: the base image is
    # moved over the actual image, so the captured screenshot becomes the
    # recorded baseline again. This is the file-mutating half of the verify
    # flow, kept explicit and separate from the pure "are they different?"
    # question. Idempotent: a second call is a no-op.
    def archive_baseline!
      return unless compare && !compare.different? && compare.base_image_path.exist?

      FileUtils.mv(compare.base_image_path, compare.image_path, force: true)
    end

    # Raise on an unsuppressed mismatch. An assertion raised here (delayed:
    # false) is still registered, so the registry re-visits it at teardown:
    # the flag makes that second #validate a no-op instead of a second failure.
    def validate!
      error_msg = validate
      @validated = true

      raise SnapDiff::ExpectationNotMet.new(error_msg, caller) if error_msg
    end

    # Verifies that all scheduled screenshots do not show any unintended differences.
    #
    # @param screenshots [Array(Array(Array(String), String, Comparison))] The list of match screenshots jobs. Defaults to all screenshots taken during the test.
    # @return [Array, nil] Returns an array of error messages if there are screenshot differences, otherwise nil.
    # @note This method is typically called at the end of a test to assert all screenshots are as expected.
    def self.verify_screenshots!(screenshots)
      return unless SnapDiff.config.active? && SnapDiff.config.fail_on_difference

      test_screenshot_errors = screenshots.map do |assertion|
        assertion.validate
      end

      test_screenshot_errors.compact!

      test_screenshot_errors.empty? ? nil : test_screenshot_errors
    end

    private

    FRAME = /\A(.+?):(\d+)(?::in |\z)/
    private_constant :FRAME

    # The line of the user's code that took the screenshot: the first frame
    # in a real file outside this gem, installed gems and Ruby's own library.
    # Matchers and helpers in between (e.g. rspec-expectations under
    # match_screenshot) are skipped without counting their depth.
    def call_site
      frames = Array(caller)
      frame = frames.find { |candidate| user_code?(candidate) } || frames.first
      path, line = frame&.match(FRAME)&.captures
      path ? "#{display_path(path)}:#{line}" : frame
    end

    def user_code?(frame)
      path = frame[FRAME, 1] or return false
      return false unless File.file?(path)

      expanded = File.expand_path(path)
      library_roots.none? { |root| expanded.start_with?(root) }
    end

    def library_roots
      ruby_dirs = RbConfig::CONFIG.values_at("rubylibdir", "sitelibdir", "vendorlibdir")
      [BacktraceFilter::LIB_DIRECTORY, *Gem.path, Gem.default_dir, *ruby_dirs]
        .reject { |dir| dir.to_s.empty? }
        .map { |dir| File.expand_path(dir) + File::SEPARATOR }
    end

    # Relative to the configured root when the file is inside it, as the
    # failure message's artifact paths are; otherwise as Ruby recorded it,
    # which resolves from where the test command ran.
    def display_path(path)
      relative = Pathname(path).expand_path.relative_path_from(SnapDiff.config.root).to_path
      relative.start_with?("..") ? path : relative
    end
  end

  class AssertionRegistry
    attr_reader :assertions, :screenshot_namer, :new_screenshots

    def initialize
      @assertions = []
      @new_screenshots = []
      @checked_out_baselines = Set.new
      @screenshot_namer = SnapDiff::ScreenshotNamer.new
    end

    # Called by Snap#checkout_base_screenshot when git really handed us a
    # baseline. Same thread as the reading below -- a test's checkout and
    # its comparison happen in one call stack -- so no synchronization is
    # needed or wanted here.
    def record_baseline_checkout(name)
      @checked_out_baselines << name
    end

    # True when git handed us a baseline for `name` in this test: a missing
    # baseline file then means it disappeared, not that none was committed.
    def baseline_checked_out?(name)
      @checked_out_baselines.include?(name)
    end

    def add_assertion(assertion)
      return unless assertion&.compare

      @assertions.push(assertion)

      assertion
    end

    def assertions_present?
      !@assertions.empty?
    end

    # "No baseline exists" reaches here for two very different reasons. One
    # is legitimate and warned about: nothing was ever committed for this
    # name. The other is impossible in a correct run -- git gave us a
    # baseline moments ago and it is gone now -- and used to be recorded as
    # if it were the first, leaving the test green having compared nothing.
    # That is the silently-wrong case measured in #217: two concurrent
    # tests asserting the SAME name, where one's archive_baseline! moves
    # the baseline the other just checked out.
    def record_new_screenshot(name)
      raise SnapDiff::Error.new(<<~ERROR.chomp, caller) if baseline_checked_out?(name)
        The baseline for '#{name}' was checked out and then disappeared before it could be compared -- nothing was verified.
        Every artifact path derives from the screenshot name alone, so two tests asserting '#{name}' at the same time race on one set of files: the one that finishes first archives the baseline the other is still using.
        Give those screenshots distinct names, or do not run them concurrently.
      ERROR

      @new_screenshots.push(name)
    end

    def new_screenshots_present?
      !@new_screenshots.empty?
    end

    def verify(screenshots = assertions)
      result = ScreenshotAssertion.verify_screenshots!(screenshots)
      return unless result

      raise SnapDiff::ExpectationNotMet.new(result.join("\n\n"), failed_assertions.first.caller)
    end

    def failed_assertions
      assertions.filter { |screenshot_assert| screenshot_assert.compare&.different? }
    end

    def reset
      @assertions.clear
      @new_screenshots.clear
      @checked_out_baselines.clear
      @screenshot_namer = SnapDiff::ScreenshotNamer.new
    end
  end
end
