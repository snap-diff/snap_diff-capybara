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
  ENV["RBS_TEST_TARGET"] ||= "Capybara::Screenshot::Diff::*"

  t.libs << "test"
  t.ruby_opts << "-r rbs/test/setup"
  t.test_files = FileList["test/**/*_test.rb"]
end
