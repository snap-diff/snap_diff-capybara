# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in capybara-screenshot-diff.gemspec
gemspec path: __dir__

gem "oily_png", platform: :ruby

gem "image_processing", require: false
gem "ruby-vips", require: false
