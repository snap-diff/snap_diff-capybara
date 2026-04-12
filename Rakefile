# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

Rake::TestTask.new("test:unit") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/unit/**/*_test.rb"]
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
  patterns = ["**/*.diff.png", "**/*.base.diff.png", "**/*.heatmap.diff.png",
    "**/*.diff.webp", "**/*.base.diff.webp", "**/*.heatmap.diff.webp",
    "**/snap_diff_report.html"]
  removed = patterns.flat_map { |p| Dir.glob("tmp/#{p}") + Dir.glob("doc/screenshots/#{p}") }
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
