# frozen_string_literal: true

require "snap_diff/vcs"

module Capybara
  module Screenshot
    module Diff
      Vcs = SnapDiff::Vcs
    end
  end
end
