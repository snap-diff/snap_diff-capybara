# frozen_string_literal: true

require "rack/files"
require_relative "integrations/minitest"

module SnapDiff
  def self.serve(directory, root: Dir.pwd)
    Capybara.app = Rack::Files.new(directory)
    Capybara::Screenshot.root = root
  end
end
