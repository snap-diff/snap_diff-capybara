# frozen_string_literal: true

# Generate a sample HTML report for manual testing.
# Uses absolute file:// paths so images load when opened directly in a browser.

require "bundler/setup"
require "capybara_screenshot_diff"
require "capybara_screenshot_diff/minitest"
require "capybara/screenshot/diff"
require "capybara_screenshot_diff/reporters/html"

output_path = CapybaraScreenshotDiff::Reporters::HTML.default_output_path

# Build real comparisons using the gem's own ImageCompare.
# Each pair gets a unique copy of the base image to avoid annotation file conflicts.
pairs = [
  {name: "islands-map", base: "a", new: "b"},
  {name: "islands-variant", base: "a", new: "c"},
  {name: "portrait-layout", base: "portrait", new: "portrait_b"}
]

embed = ARGV.include?("--embed") || !!ENV["CI"]
reporter = CapybaraScreenshotDiff::Reporters::HTML.new(output_path: output_path, embed_images: embed)
fixtures = File.expand_path("../test/fixtures/images", __dir__)
tmp_dir = File.expand_path("../tmp/sample_images", __dir__)
FileUtils.mkdir_p(tmp_dir)

assertions = pairs.map do |pair|
  # Copy to tmp so each comparison has its own base/new files for annotations
  base_copy = "#{tmp_dir}/#{pair[:name]}_base.png"
  new_copy = "#{tmp_dir}/#{pair[:name]}_new.png"
  FileUtils.cp("#{fixtures}/#{pair[:base]}.png", base_copy)
  FileUtils.cp("#{fixtures}/#{pair[:new]}.png", new_copy)

  compare = Capybara::Screenshot::Diff::ImageCompare.new(new_copy, base_copy, driver: :vips)
  compare.processed

  CapybaraScreenshotDiff::ScreenshotAssertion.new(pair[:name]).tap { |a| a.compare = compare }
end

# Add passing assertions (identical images = no difference)
passing = %w[dashboard settings profile users].map do |name|
  compare = Capybara::Screenshot::Diff::ImageCompare.new("#{fixtures}/a.png", "#{fixtures}/a.png")
  compare.processed
  CapybaraScreenshotDiff::ScreenshotAssertion.new(name).tap { |a| a.compare = compare }
end

reporter.record(assertions + passing)
reporter.finalize

puts "Screenshots: #{reporter.failed} failed, #{reporter.passed} passed, #{reporter.total} total"
