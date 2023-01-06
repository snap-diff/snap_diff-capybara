# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

Rake::TestTask.new("test:integration") do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/integration/**/*_test.rb"]
end

Rake::TestTask.new("test:signatures") do |t|
  ENV["RBS_TEST_DOUBLE_SUITE"] ||= "minitest"
  ENV["RBS_TEST_TARGET"] ||= "Capybara::Screenshot::Diff::*"
  ENV["RBS_TEST_OPT"] ||= "-rset -rpathname -Isig"

  t.libs << "test"
  t.ruby_opts << "-r rbs/test/setup"
  t.test_files = FileList["test/**/*_test.rb"]
end

task "clobber" do
  puts "Cleanup tmp/*.png"
  FileUtils.rm_rf(Dir["./tmp/*"])
end

task "test:benchmark" do
  require_relative "./scripts/benchmark/find_region_benchmark"
  benchmark = Capybara::Screenshot::Diff::Drivers::FindRegionBenchmark.new

  puts "For Medium Screen Size: 800x600"
  benchmark.for_medium_size_screens

  puts ""
  puts "*" * 100

  puts "For Small Screen Size: 80x60"
  benchmark.for_small_images
end
