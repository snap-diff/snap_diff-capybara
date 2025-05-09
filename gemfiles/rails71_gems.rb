# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "activesupport", "~> 7.1.0", require: %w[logger active_support/deprecator active_support]
gem "actionpack", "~> 7.1.0", require: %w[action_controller action_dispatch]
