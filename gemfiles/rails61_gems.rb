# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "actionpack", "~> 6.1.0", "< 6.2"
gem "capybara", ">= 3.26"
