# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in capybara-screenshot-diff.gemspec
gemspec path: __dir__

gem "rake"

# ruby-vips is a gemspec runtime dependency since 2.1 (the only backend), so
# it is not listed here. chunky_png/oily_png went with the chunky_png driver.

group :test do
  gem "capybara", ">= 3.26"
  gem "mutex_m" # Needed for RubyMine debugging.  Try removing it.
  gem "minitest", "< 6", require: false
  gem "minitest-mock", require: false
  gem "minitest-stub-const", require: false
  gem "simplecov", require: false
  gem "rspec", require: false
end

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
end
