# frozen_string_literal: true

require "open3"
require_relative "os"

module SnapDiff
  module Vcs
    # `-C <dir>` sets the working directory, but GIT_DIR/GIT_WORK_TREE OVERRIDE
    # it -- so a suite launched from a git hook (which exports both) reads the
    # WRONG repository. Every baseline lookup then fails, and because
    # `fail_if_new` is false locally, screenshots are recorded as new and the
    # tests PASS. Scrubbing them makes `-C` mean what this code already assumes.
    GIT_ENV = {"GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil}.freeze

    @git_roots = {}
    @git_roots_lock = Mutex.new

    def self.checkout_vcs(root, screenshot_path, checkout_path)
      root_path = root.to_s
      git_root = git_root_for(root_path)
      return false unless git_root

      vcs_file_path = Pathname.new(screenshot_path).expand_path.relative_path_from(Pathname.new(git_root)).to_s

      if SnapDiff.config.use_lfs
        tmp_path = "#{checkout_path}.tmp"
        success = system(GIT_ENV, "git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: tmp_path, err: File::NULL)
        if success
          system(GIT_ENV, "git", "-C", root_path, "lfs", "smudge", in: tmp_path, out: checkout_path.to_s, err: File::NULL)
        end
        File.delete(tmp_path) if File.exist?(tmp_path)
      else
        success = system(GIT_ENV, "git", "-C", root_path, "show", "HEAD:#{vcs_file_path}", out: checkout_path.to_s, err: File::NULL)
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
    #
    # Synchronized because the lookup itself is what must not be duplicated:
    # MRI releases the GVL for the whole of `Open3.capture3`, so eight threads
    # asking about one root all miss `key?` before any of them writes -- eight
    # spawns, the exact cost this cache exists to remove. Threads are the
    # default parallel mode on JRuby, which has no GVL to make the Hash write
    # safe either. Holding the lock across the spawn is deliberate: callers
    # almost always share one root, so the other threads wait once and then
    # read the cache, which is the outcome we want.
    def self.git_root_for(root_path)
      @git_roots_lock.synchronize do
        next @git_roots[root_path] if @git_roots.key?(root_path)

        git_root, _, status = Open3.capture3(GIT_ENV, "git", "-C", root_path, "rev-parse", "--show-toplevel")
        @git_roots[root_path] = status.success? && git_root.chomp
      end
    end
  end
end
