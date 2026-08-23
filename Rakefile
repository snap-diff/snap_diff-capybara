# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

# `test:canonical` was "everything except test/legacy/", i.e. what had to
# still pass once the v1 surface was deleted. 2.1 deleted it, test/legacy/
# went with it, and the two tasks converged on the same file list -- so the
# second name is gone rather than kept as an alias for one thing.
#
# `rake test`             -- THE gate.
# `rake test:unit`        -- unit-sized tests.
# `rake test:integration` -- browser-driven tests.
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
# `test:benchmark` is deleted rather than repointed: it required
# scripts/benchmark/find_region_benchmark, which is not in this repo, so the
# task raised LoadError on every invocation -- and its body named a v1
# constant this release removes.
