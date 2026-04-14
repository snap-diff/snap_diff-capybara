# frozen_string_literal: true

require "open3"
require_relative "os"

module Capybara
  module Screenshot
    module Diff
      module Vcs
        def self.checkout_vcs(root, screenshot_path, checkout_path)
          root_path = root.to_s
          git_env = {"GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil}
          git_root, _, status = Open3.capture3(git_env, "git", "-C", root_path, "rev-parse", "--show-toplevel")
          return false unless status.success?

          git_root = git_root.chomp
          vcs_file_path = Pathname.new(screenshot_path).expand_path.relative_path_from(Pathname.new(git_root)).to_s

          if Screenshot.use_lfs
            tmp_path = "#{checkout_path}.tmp"
            success = system(git_env, "git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: tmp_path, err: File::NULL)
            if success
              system(git_env, "git", "-C", root_path, "lfs", "smudge", in: tmp_path, out: checkout_path.to_s, err: File::NULL)
            end
            File.delete(tmp_path) if File.exist?(tmp_path)
          else
            success = system(git_env, "git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: checkout_path.to_s, err: File::NULL)
          end

          unless success
            checkout_path.delete if checkout_path.exist?
            return false
          end

          true
        end
      end
    end
  end
end
