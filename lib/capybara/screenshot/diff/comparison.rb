# frozen_string_literal: true

module Capybara::Screenshot::Diff
  class Comparison < Struct.new(:new_image, :base_image, :options, :driver, :new_image_path, :base_image_path)
  end
end
