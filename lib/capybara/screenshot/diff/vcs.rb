# frozen_string_literal: true

require_relative "os"

module Capybara
  module Screenshot
    module Diff
      module Vcs

        def self.checkout_vcs(root, screenshot_path, checkout_path)
          if svn?(root)
            restore_svn_revision(screenshot_path, checkout_path)
          else
            restore_git_revision(screenshot_path, checkout_path, root: root)
          end
        end

        def self.svn?(root)
          (root / ".svn").exist?
        end

        SILENCE_ERRORS = Os::ON_WINDOWS ? "2>nul" : "2>/dev/null"

        def self.restore_git_revision(screenshot_path, checkout_path = screenshot_path, root:)
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

        def self.restore_svn_revision(screenshot_path, checkout_path)
          committed_file_name = screenshot_path + "../.svn/text-base/" + "#{screenshot_path.basename}.svn-base"
          if committed_file_name.exist?
            FileUtils.cp(committed_file_name, checkout_path)
            return true
          end

          svn_info = `svn info #{screenshot_path} #{SILENCE_ERRORS}`
          if svn_info.present?
            wc_root = svn_info.slice(/(?<=Working Copy Root Path: ).*$/)
            checksum = svn_info.slice(/(?<=Checksum: ).*$/)

            if checksum
              committed_file_name = "#{wc_root}/.svn/pristine/#{checksum[0..1]}/#{checksum}.svn-base"
              FileUtils.cp(committed_file_name, checkout_path)
              return true
            end
          end

          false
        end

      end
    end
  end
end
