# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "activesupport", "~> 8.0.0"
gem "actionpack", "~> 8.0.0"
