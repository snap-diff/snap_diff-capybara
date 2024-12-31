# frozen_string_literal: true

gems = "#{File.dirname __dir__}/gems.rb"
eval File.read(gems), binding, gems

git "https://github.com/rails/rails.git" do
  gem "actionpack"
end
