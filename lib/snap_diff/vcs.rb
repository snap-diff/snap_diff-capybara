# frozen_string_literal: true

require "open3"
require_relative "os"

module SnapDiff
  module Vcs
    @git_roots = {}

    def self.checkout_vcs(root, screenshot_path, checkout_path)
      root_path = root.to_s
      git_root = git_root_for(root_path)
      return false unless git_root

      vcs_file_path = Pathname.new(screenshot_path).expand_path.relative_path_from(Pathname.new(git_root)).to_s

      if SnapDiff.config.use_lfs
        tmp_path = "#{checkout_path}.tmp"
        success = system("git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: tmp_path, err: File::NULL)
        if success
          system("git", "-C", root_path, "lfs", "smudge", in: tmp_path, out: checkout_path.to_s, err: File::NULL)
        end
        File.delete(tmp_path) if File.exist?(tmp_path)
      else
        success = system("git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: checkout_path.to_s, err: File::NULL)
      end

      unless success
        checkout_path.delete if checkout_path.exist?
        return false
      end

      true
    end

    # `git rev-parse --show-toplevel` costs a process spawn (~6ms) and used to
    # run once per screenshot -- 200 screenshots, 200 spawns, all answering the
    # same question. The repository a directory belongs to does not change
    # while the suite runs, so remember it per directory. `false` (not a repo)
    # is remembered too: that is the every-assertion answer for anyone whose
    # screenshots live outside a git checkout.
    def self.git_root_for(root_path)
      return @git_roots[root_path] if @git_roots.key?(root_path)

      git_root, _, status = Open3.capture3("git", "-C", root_path, "rev-parse", "--show-toplevel")
      @git_roots[root_path] = status.success? && git_root.chomp
    end
  end
end
