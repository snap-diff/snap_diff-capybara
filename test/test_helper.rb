# frozen_string_literal: true

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start "test_frameworks" do
    enable_coverage :branch
    minimum_coverage line: 90, branch: 68

    add_filter("gemfiles")
    add_filter("test")
  end
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "pathname"
TEST_IMAGES_DIR = Pathname.new(File.expand_path("images", __dir__))

# NOTE: Simulate Rails Environment
module Rails
  def self.root
    Pathname("../tmp").expand_path(__dir__)
  end

  def self.application
    Rack::Builder.new {
      use(Rack::Static, urls: [""], root: "test/fixtures/app", index: "index.html")
      run ->(_env) { [200, {}, []] }
    }.to_app
  end
end

require "capybara/screenshot/diff"
require "minitest/autorun"
require "capybara/minitest"

require "capybara/dsl"
Capybara.disable_animation = true
Capybara.server = :puma, {Silent: true}
Capybara.threadsafe = true
Capybara.app = Rails.application

require "support/stub_test_methods"

class ActiveSupport::TestCase
  self.file_fixture_path = Pathname.new(File.expand_path("fixtures/app", __dir__))

  teardown do
    FileUtils.rm_rf Capybara::Screenshot.screenshot_area_abs
    FileUtils.rm_rf Dir[Capybara::Screenshot.root / "*.png"]
  end

  def optional_test
    unless ENV["DISABLE_SKIP_TESTS"]
      skip "This is optional test! To enable need to provide DISABLE_SKIP_TESTS=1"
    end
  end
end
