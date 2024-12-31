# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

gem "actionpack", "~> 7.0.0"
gem 'mutex_m'
gem 'drb'
gem 'bigdecimal'
