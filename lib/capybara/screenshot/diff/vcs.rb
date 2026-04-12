# frozen_string_literal: true

require_relative "os"

module Capybara
  module Screenshot
    module Diff
      module Vcs
        SILENCE_ERRORS = Os::ON_WINDOWS ? "2>nul" : "2>/dev/null"

        def self.checkout_vcs(root, screenshot_path, checkout_path)
          vcs_file_path = screenshot_path.relative_path_from(root)
          redirect_target = "#{checkout_path} #{SILENCE_ERRORS}"
          show_command = "git show HEAD~0:./#{vcs_file_path}"

          Dir.chdir(root) do
            if Screenshot.use_lfs
              system("#{show_command} > #{checkout_path}.tmp #{SILENCE_ERRORS}", exception: !!ENV["DEBUG"])

              `git lfs smudge < #{checkout_path}.tmp > #{redirect_target}` if $CHILD_STATUS == 0

              File.delete "#{checkout_path}.tmp"
            else
              system("#{show_command} > #{redirect_target}", exception: !!ENV["DEBUG"])
            end
          end

          if $CHILD_STATUS != 0
            checkout_path.delete if checkout_path.exist?
            false
          else
            true
          end
        end
      end
    end
  end
end
