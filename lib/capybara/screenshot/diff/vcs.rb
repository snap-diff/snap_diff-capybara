# frozen_string_literal: true

require_relative "os"

module Capybara
  module Screenshot
    module Diff
      module Vcs
        SILENCE_ERRORS = Os::ON_WINDOWS ? "2>nul" : "2>/dev/null"

        def self.restore_git_revision(screenshot_path, checkout_path)
          vcs_file_path = screenshot_path.relative_path_from(Screenshot.root)

          redirect_target = "#{checkout_path} #{SILENCE_ERRORS}"
          show_command = "git show HEAD~0:./#{vcs_file_path}"
          if Screenshot.use_lfs
            `#{show_command} | git lfs smudge > #{redirect_target} ; exit ${PIPESTATUS[0]}`
          else
            `#{show_command} > #{redirect_target}`
          end

          if $CHILD_STATUS != 0
            FileUtils.rm_f(checkout_path)
            false
          else
            true
          end
        end

        def self.checkout_vcs(screenshot_path, checkout_path)
          if svn?
            restore_svn_revision(screenshot_path, checkout_path)
          else
            restore_git_revision(screenshot_path, checkout_path)
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

        def self.svn?
          (Screenshot.screenshot_area_abs / ".svn").exist?
        end
      end
    end
  end
end
