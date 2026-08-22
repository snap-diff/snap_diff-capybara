# frozen_string_literal: true

require "rspec/core"
require_relative "../dsl"
# See the matching comment in integrations/minitest.rb.
require "snap_diff/screenshot_assertion"
require "snap_diff/reporting"

RSpec::Matchers.define :match_screenshot do |name, **options|
  description { "match screenshot '#{name}'" }

  match do |_page|
    assert_matches_screenshot(name, **options)
    true
  end

  failure_message do
    "Expected page to match screenshot '#{name}'"
  end

  failure_message_when_negated do
    "Expected page not to match screenshot '#{name}'"
  end
end

RSpec.configure do |config|
  config.include SnapDiff::DSL, type: :feature
  config.include SnapDiff::DSL, type: :system

  config.before do
    if self.class.include?(SnapDiff::DSL)
      SnapDiff::BrowserHelpers.resize_window_if_needed
    end
  end

  # `append_after` (as opposed to the default `after`, which prepends) adds
  # this hook to the *end* of the after-hook chain regardless of when it's
  # registered relative to the user's own `after`/`config.after` hooks. RSpec
  # runs `after(:each)` hooks in reverse registration order, so a plain
  # `config.after` here would run BEFORE a user hook registered earlier in
  # their own spec_helper (before this file was required) -- and if that
  # later-running user hook raises, its exception gets folded into
  # `pending_exception` instead of `example.exception`, silently masking the
  # failure behind our pending skip. `append_after` runs after the full user
  # after-chain no matter the registration order, closing that gap.
  config.append_after do |example|
    if self.class.include?(SnapDiff::DSL)
      begin
        SnapDiff.session.verify

        # Never mask a real failure with a pending marker. Kept as
        # defense-in-depth: `append_after` observes failures from plain
        # `after`/`prepend_after` user hooks, but appended hooks run FIFO,
        # so a user `append_after` registered after this gem still runs
        # later than us — RSpec has no "run absolutely last" construct.
        # Mitigation for such consumers: require this gem last.
        if example.exception.nil? && (msg = SnapDiff.pending_screenshots_message)
          skip(msg)
        end
      rescue SnapDiff::ExpectationNotMet => e
        raise RSpec::Expectations::ExpectationNotMetError.new(e.message).tap { |ex| ex.set_backtrace(e.backtrace) }
      ensure
        SnapDiff.reset
      end
    end
  end

  config.after(:suite) { SnapDiff::Reporting.finalize! }
end
