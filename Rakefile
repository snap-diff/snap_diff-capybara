# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

# THE 2.1 SPLIT.
#
# test/legacy/ holds every test whose SUBJECT is the v1 compatibility surface
# -- the old Capybara::Screenshot / CapybaraScreenshotDiff namespaces, their
# deprecation warnings, and the gates that keep lib/capybara* alias-only.
# Those tests guard the v1 contract for the whole 2.x line, so they stay and
# stay green; in 2.1 they are deleted by the same commit that deletes what
# they test:
#
#   git rm -r lib/capybara* lib/capybara_screenshot_diff.rb \
#             lib/snap_diff/legacy_shims.rb lib/snap_diff/deprecation.rb \
#             test/legacy
#
# A directory rather than a list in this file: there is nothing to keep in
# sync, and the deletion is one `git rm -r`.
#
# `rake test`           -- everything, today's gate.
# `rake test:canonical` -- exactly what must still pass once test/legacy and
#                          the v1 trees are gone. THE 2.1 GATE.
# `rake test:unit`      -- unit-sized tests; test/legacy is unit-sized too
#                          (legacy/ marks lifetime, not kind), so it is in.
LEGACY_SURFACE_TESTS = "test/legacy/**/*_test.rb"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Run every test that must survive the 2.1 deletion of the v1 surface"
Rake::TestTask.new("test:canonical") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude(LEGACY_SURFACE_TESTS)
end

Rake::TestTask.new("test:unit") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/unit/**/*_test.rb", LEGACY_SURFACE_TESTS]
end

Rake::TestTask.new("test:integration") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/integration/**/*_test.rb"]
end

desc "Run all tests with coverage"
task :coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task["test"].invoke
end

desc "Generate sample HTML report. Use bin/rake 'report:sample[embed]' for base64 images"
task "report:sample", [:embed] do |_t, args|
  embed_arg = args[:embed] ? "--embed" : ""
  ruby "scripts/generate_sample_report.rb #{embed_arg}"
end

desc "Remove screenshot diff artifacts (keeps baselines)"
task "snap_diff:clean" do
  patterns = ["**/*.diff.png", "**/*.base.png", "**/*.base.diff.png", "**/*.heatmap.diff.png",
    "**/*.diff.webp", "**/*.base.webp", "**/*.base.diff.webp", "**/*.heatmap.diff.webp",
    "**/snap_diff_report.html"]
  removed = patterns.flat_map { |p| Dir.glob("tmp/#{p}") + Dir.glob("doc/screenshots/#{p}") }.uniq
  removed.each { |f| FileUtils.rm_f(f) }
  puts "Removed #{removed.size} diff artifacts"
end

task "clobber" do
  puts "Cleanup tmp/"
  FileUtils.rm_rf(Dir["./tmp/*"])
end

task "test:benchmark" do
  require_relative "scripts/benchmark/find_region_benchmark"
  benchmark = Capybara::Screenshot::Diff::Drivers::FindRegionBenchmark.new

  puts "For Medium Screen Size: 800x600"
  benchmark.for_medium_size_screens

  puts ""
  puts "*" * 100

  puts "For Small Screen Size: 80x60"
  benchmark.for_small_images
end
