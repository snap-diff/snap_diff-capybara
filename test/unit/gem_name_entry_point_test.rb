# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# `Bundler.require` -- the default for Rails, and for anyone who does not
# write `require: false` -- requires the gem's OWN NAME, so lib/<gem-name>.rb
# loads for every consumer whatever test framework they use. It may therefore
# hard-require nothing outside the gem's declared runtime dependencies, and
# minitest is not one of them: the gemspec declares capybara only.
#
# It used to. An RSpec-only bundle died at boot with
#
#   There was an error while trying to load the gem 'snap_diff-capybara'.
#   Gem Load Error is: cannot load such file -- minitest
#
# from a gem that ships a first-class RSpec integration. Both directions
# matter: minitest absent must load, minitest present must still auto-
# activate the assertions, which is the documented zero-require Rails path.
#
# The v1 gem-name entry (deleted in 3.0) is probed the same way from
# test/legacy/legacy_entry_point_probe_test.rb, which reuses .probe below.
class GemNameEntryPointTest < ActiveSupport::TestCase
  LIB = File.expand_path("../../lib", __dir__)

  # Opens every probe: a probe that quietly tested the wrong environment
  # would "prove" whatever we hoped it would.
  GATE = {
    false => <<~RUBY,
      begin
        require "minitest"
        abort("GATE: minitest is loadable in this probe, so it proves nothing")
      rescue LoadError
      end
    RUBY
    true => <<~RUBY
      begin
        require "minitest"
      rescue LoadError
        abort("GATE: minitest is NOT loadable in this probe, so it proves nothing")
      end
    RUBY
  }.freeze

  # Runs +script+ in a fresh process with the gem's lib/ on the load path and
  # the cwd OUTSIDE the project: inside it, RubyGems re-adds
  # `-rbundler/setup` and the gemspec unshifts the real lib/, so the probe
  # would silently exercise the development bundle instead of what it set up.
  #
  # With <tt>minitest: false</tt> a shim directory shadowing "minitest" goes
  # FIRST on the load path, so `require "minitest"` raises LoadError exactly
  # as it does in a bundle without the gem. (A real `bundle install` in a
  # scratch Gemfile reproduces the same thing and was used to confirm this
  # one, but it needs the network and has no place in the unit suite.)
  #
  # @return [Array(String, String, Process::Status)] stdout, stderr, status
  def self.probe(script, minitest: true)
    Dir.mktmpdir do |dir|
      load_paths = ["-I#{LIB}"]

      unless minitest
        shim = File.join(dir, "shim")
        Dir.mkdir(shim)
        # No LoadError#path: RubyGems retries a require whose LoadError names
        # the same path, and would then activate the real minitest gem.
        File.write(File.join(shim, "minitest.rb"), %(raise LoadError, "cannot load such file -- minitest"\n))
        load_paths.unshift("-I#{shim}")
      end

      Open3.capture3(RbConfig.ruby, *load_paths, "-e", GATE.fetch(minitest) + script, chdir: dir)
    end
  end

  test "the gem-name entry point loads in a bundle without minitest" do
    # Non-interpolating heredoc: `#{}` in a probe script belongs to the
    # CHILD, and this suite has SnapDiff loaded, so interpolating here would
    # answer every question with the parent's own state.
    out, err, status = self.class.probe(<<~'RUBY', minitest: false)
      require "snap_diff-capybara"
      puts "VERSION:#{SnapDiff::VERSION}"
      puts "DSL:#{!defined?(SnapDiff::DSL).nil?}"
      puts "ASSERTIONS:#{!defined?(SnapDiff::Minitest::Assertions).nil?}"
    RUBY

    assert_predicate status, :success?, "boot must not fail without minitest:\n#{out}\n#{err}"
    assert_match(/VERSION:\d+\./, out, "the gem's own surface must still load")
    assert_includes out, "DSL:true"
    assert_includes out, "ASSERTIONS:false", "the Minitest assertions cannot be live without minitest"
  end

  # A gem that loads but does nothing, silently, is its own bug report.
  test "the gem-name entry point says where to go when it activated nothing" do
    out, err, status = self.class.probe(%(require "snap_diff-capybara"), minitest: false)

    assert_predicate status, :success?, "#{out}\n#{err}"
    assert_match(%r{snap_diff/integrations/rspec}, err)
    assert_match(/require: false/, err, "the message must name the way to silence it")
  end

  # The other direction: the documented zero-require Rails path.
  test "the gem-name entry point still auto-activates the Minitest assertions when minitest is present" do
    out, err, status = self.class.probe(<<~'RUBY')
      require "snap_diff-capybara"
      puts "ASSERTIONS:#{!defined?(SnapDiff::Minitest::Assertions).nil?}"
    RUBY

    assert_predicate status, :success?, "#{out}\n#{err}"
    assert_equal "ASSERTIONS:true\n", out
    assert_no_match(%r{snap_diff/integrations/rspec}, err, "nothing to say when the assertions are live")
  end
end
