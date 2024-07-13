# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in capybara-screenshot-diff.gemspec
gemspec path: __dir__

gem "rake"

# Image processing libraries
gem "chunky_png", ">= 1.3", require: false
gem "oily_png", platform: :ruby, git: "https://github.com/wvanbergen/oily_png", ref: "44042006e79efd42ce4b52c1d78a4c70f0b4b1b2"
gem "ruby-vips", require: false

# Test
gem "minitest", require: false
gem "minitest-stub-const", require: false
gem "simplecov", require: false
gem "rspec", require: false

# Capybara Server
gem "puma", require: false
gem "rackup", require: false

# Capybara Drivers
gem "cuprite", require: false
gem "selenium-webdriver", ">= 4.11", require: false

# Test Frameworks
# gem "cucumber", require: false
# gem "cucumber-rails", require: false

group :tools do
  gem "standard", require: false
  gem "rbs", require: false, platform: :ruby
end
