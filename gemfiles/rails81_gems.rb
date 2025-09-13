# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "activesupport", "~> 8.1.0.beta1"
gem "actionpack", "~> 8.1.0.beta1"
