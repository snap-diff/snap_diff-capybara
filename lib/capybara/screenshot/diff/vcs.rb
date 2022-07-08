# frozen_string_literal: true

require_relative "os"
module Capybara
  module Screenshot
    module Diff
      module Vcs
        SILENCE_ERRORS = Os::ON_WINDOWS ? "2>nul" : "2>/dev/null"

        def restore_git_revision(name, target_file_name)
          redirect_target = "#{target_file_name} #{SILENCE_ERRORS}"
          show_command = "git show HEAD~0:./#{Capybara::Screenshot.screenshot_area}/#{name}.png"
          if Capybara::Screenshot.use_lfs
            `#{show_command} | git lfs smudge > #{redirect_target}`
          else
            `#{show_command} > #{redirect_target}`
          end
          FileUtils.rm_f(target_file_name) unless $CHILD_STATUS == 0
        end

        def checkout_vcs(name, old_file_name, new_file_name)
          svn_file_name = "#{Capybara::Screenshot.screenshot_area_abs}/.svn/text-base/#{name}.png.svn-base"

          if File.exist?(svn_file_name)
            committed_file_name = svn_file_name
            FileUtils.cp committed_file_name, old_file_name
          else
            svn_info = `svn info #{new_file_name} #{SILENCE_ERRORS}`
            if svn_info.present?
              wc_root = svn_info.slice(/(?<=Working Copy Root Path: ).*$/)
              checksum = svn_info.slice(/(?<=Checksum: ).*$/)
              if checksum
                committed_file_name = "#{wc_root}/.svn/pristine/#{checksum[0..1]}/#{checksum}.svn-base"
                FileUtils.cp committed_file_name, old_file_name
              end
            else
              restore_git_revision(name, old_file_name)
            end
          end
        end
      end
    end
  end
end
