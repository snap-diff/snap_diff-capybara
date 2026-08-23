# frozen_string_literal: true

require "test_helper"
require "open3"

# Kaizen guard for support-file transitive-require gaps (same subprocess
# pattern as snap_diff_test.rb's standalone-load regression test).
#
# test_helper.rb preloads the whole gem, so a support file missing one of its
# own requires still loads fine in most suite runs and only breaks in the CI
# matrix cell with a different load order — exactly how
# setup_capybara_drivers.rb broke on selenium_chrome_headless + vips (it used
# SnapDiff::Os without requiring it, fixed in b7ada5e). This test requires
# every test/support file in a bare subprocess with only capybara core
# preloaded. Scope: it catches missing requires for constants referenced
# AT LOAD TIME under this process's env; references hidden behind env guards
# (e.g. CAPYBARA_DRIVER branches not taken here) or inside method bodies
# still escape it.
#
# Currently every support file is expected to be bare-loadable: each one
# requires what it uses (rack/action_controller in setup_rails_app,
# active_support/concern in dsl_stub and driver_contract_tests, the gem's own
# files elsewhere). If a future support file legitimately needs more context
# than "capybara is loaded", list it in SKIP with the reason.
#
# The v1 entry points -- their advertised constants, the
# CapybaraScreenshotDiff session surface, and the eager user-facing
# constants under the old names -- are probed the same way from
# test/legacy/legacy_entry_point_probe_test.rb, which is deleted with the v1
# trees in 3.0.
class SupportLoadProbeTest < ActiveSupport::TestCase
  SKIP = {
    # "support/example" => "why it cannot load bare"
  }.freeze

  test "every test/support file is requirable with only capybara core loaded" do
    project_root = File.expand_path("../..", __dir__)
    support_files = Dir.chdir(File.join(project_root, "test")) { Dir["support/**/*.rb"] }.sort
    assert_operator support_files.size, :>=, 10, "probe should see the support files"

    failures = support_files.filter_map do |file|
      require_path = file.sub(/\.rb\z/, "")
      next if SKIP.key?(require_path)

      script = "require \"capybara\"; require #{require_path.inspect}"
      out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-Itest", "-e", script, chdir: project_root)

      "#{file}:\n#{out}" unless status.success?
    end

    assert_empty failures, <<~MSG
      Support file(s) rely on requires test_helper happens to load first.
      Add the missing require to the support file itself (or document a SKIP here):

      #{failures.join("\n\n")}
    MSG
  end

  # --- beta3 blockers: entry points must load a COMPLETE surface ---
  #
  # The canonical `snap_diff/*` requires never loaded snap_diff.rb itself,
  # so the docs' own quick start (`require "snap_diff/integrations/minitest"`)
  # left SnapDiff.configure/.start/.compare undefined, SnapDiff::VERSION
  # unresolvable, and the dual-install guard silent.

  # SnapDiff.serve is deliberately absent here: docs/snapdiff.md's object
  # map gates it behind its own `require "snap_diff/static"` (which pulls
  # rack + minitest), so the core must not carry it.
  #
  # SnapDiff.start is absent for a different reason: it is defined in
  # snap_diff/legacy_shims.rb and yields the two v1 config holders, so it
  # cannot outlive them (#235). A CANONICAL gate demanding a method 3.0
  # deletes is a gate that fails the day the deletion lands -- which is
  # exactly what it did. `.start` keeps its coverage on the legacy side:
  # test/legacy/legacy_forwarders_test.rb asserts what it yields and that it
  # applies a setting, and LEGACY_SESSION_SURFACE pins it per v1 entry point.
  CANONICAL_SURFACE = %w[
    config configure compare session reset pending_screenshots_message
  ].freeze

  # snap_diff-capybara is the canonical gem's Bundler entry point, so it is
  # probed here rather than with the v1 ones: 3.0 keeps it (repointed at
  # snap_diff/integrations/minitest), it just stops carrying the
  # CapybaraScreenshotDiff surface.
  CANONICAL_ENTRY_POINTS = {
    "snap_diff" => CANONICAL_SURFACE,
    "snap_diff/dsl" => CANONICAL_SURFACE,
    "snap_diff/integrations/minitest" => CANONICAL_SURFACE,
    "snap_diff/integrations/rspec" => CANONICAL_SURFACE,
    "snap_diff/integrations/cucumber" => CANONICAL_SURFACE,
    "snap_diff/static" => CANONICAL_SURFACE + %w[serve],
    "snap_diff-capybara" => CANONICAL_SURFACE
  }.freeze

  test "every canonical snap_diff entry point loads the full SnapDiff surface" do
    failures = CANONICAL_ENTRY_POINTS.filter_map do |entry, methods|
      self.class.probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{methods.inspect}.reject { |m| SnapDiff.respond_to?(m) }
        missing << "VERSION" unless defined?(SnapDiff::VERSION)
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Canonical entry point(s) load only a fragment of SnapDiff:

      #{failures.join("\n")}
    MSG
  end

  # Ported from the legacy entry-point probe (test/legacy/), which was the
  # only place asserting that an entry point defines its advertised
  # CONSTANTS when it is the ONLY require -- it just did so for the v1 names
  # (CapybaraScreenshotDiff::DSL, Capybara::Screenshot::Os, ...). That is the
  # f89cea2 bug class: the acyclic redesign once narrowed an entry point so
  # consumers lost the DSL, and only one CI matrix leg noticed. Same claim,
  # canonical names, canonical entries -- so 3.0 keeps the guard.
  #
  # Entry-specific on purpose: bare `snap_diff` deliberately carries neither
  # the DSL nor the reporters (see CANONICAL_SURFACE above), so a flat list
  # over all entries would be wrong rather than strict.
  CANONICAL_ADVERTISED_CONSTANTS = {
    "snap_diff/dsl" => %w[SnapDiff::DSL SnapDiff::Os SnapDiff::Comparison],
    "snap_diff/integrations/minitest" => %w[
      SnapDiff::DSL SnapDiff::Minitest::Assertions SnapDiff::Os SnapDiff::Comparison
    ],
    "snap_diff/integrations/rspec" => %w[SnapDiff::DSL SnapDiff::Os SnapDiff::Comparison],
    "snap_diff-capybara" => %w[
      SnapDiff::DSL SnapDiff::Minitest::Assertions SnapDiff::Os SnapDiff::Comparison
    ]
  }.freeze

  test "every canonical entry point defines its advertised constants standalone" do
    failures = CANONICAL_ADVERTISED_CONSTANTS.filter_map do |entry, constants|
      self.class.probe(entry, <<~RUBY)
        require #{entry.inspect}
        missing = #{constants.inspect}.reject { |c| Object.const_defined?(c) }
        abort("missing: \#{missing.join(", ")}") unless missing.empty?
      RUBY
    end

    assert_empty failures, <<~MSG
      Canonical entry point(s) no longer provide their advertised constants standalone:

      #{failures.join("\n")}
    MSG
  end

  test "every canonical snap_diff entry point runs the dual-install guard" do
    failures = CANONICAL_ENTRY_POINTS.keys.filter_map do |entry|
      self.class.probe(entry, <<~RUBY)
        require "rubygems"
        %w[capybara-screenshot-diff snap_diff-capybara].each do |name|
          Gem.loaded_specs[name] ||= Gem::Specification.new(name, "0.0.0")
        end
        begin
          require #{entry.inspect}
        rescue SnapDiff::DualInstallError
          exit 0
        end
        abort("both gems activated, but the dual-install guard stayed silent")
      RUBY
    end

    assert_empty failures, <<~MSG
      Entry point(s) bypass SnapDiff.assert_single_gem!:

      #{failures.join("\n")}
    MSG
  end

  # cucumber's World/Before/After/AfterAll only exist inside its runtime, so
  # a bare probe of a cucumber entry has to supply them or the require dies
  # before it reaches what is under test.
  CUCUMBER_RUNTIME_STUB = <<~RUBY
    def World(*) = nil
    def Before(*) = nil
    def After(*) = nil
    def AfterAll(*) = nil
  RUBY

  # Runs +script+ in a fresh process with only lib/ on the load path.
  # Returns nil on success, a failure description otherwise.
  #
  # Public, and deliberately so: test/legacy/legacy_entry_point_probe_test.rb
  # reuses it rather than keeping a second copy that would drift.
  def self.probe(entry, script)
    project_root = File.expand_path("../..", __dir__)
    preamble = entry.include?("cucumber") ? CUCUMBER_RUNTIME_STUB : ""
    out, status = Open3.capture2e(RbConfig.ruby, "-Ilib", "-e", preamble + script, chdir: project_root)

    "require \"#{entry}\" -> #{out}" unless status.success?
  end
end
