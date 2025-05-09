# frozen_string_literal: true

require "rack"
require "rackup" if Rack::RELEASE >= "3"

require "logger" # for Rails 7.0
require "action_controller"

# NOTE: Simulate Rails Environment
module Rails
  def self.root
    Pathname("../../tmp").expand_path(__dir__)
  end

  def self.application
    Rack::Builder.new {
      use(Rack::Static, urls: [""], root: "test/fixtures/app", index: "index.html")
      run ->(_env) { [200, {}, []] }
    }.to_app
  end
end
