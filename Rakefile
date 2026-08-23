# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

task default: :test

# `rake test:canonical` is gone with the thing it was defined against: it
# was "test/**/*_test.rb minus test/legacy/", i.e. exactly what had to keep
# passing once the v1 compatibility trees were deleted. 2.1 deleted them and
# test/legacy/ with them, so that task became a second name for `rake test`.
#
# The split still has a live guard, on the other side: canonical tests must
# not grow legacy references BACK (test/unit/canonical_suite_has_no_legacy_
# refs_test.rb, and its lib/ twin core_tree_has_no_legacy_deps_test.rb).
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
