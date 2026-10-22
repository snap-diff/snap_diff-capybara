# frozen_string_literal: true

# Accept screenshot baselines from a PR comment or a new issue (the report's
# "Commit decisions" button opens one prefilled):
#
#   /snap-diff accept run=<run_id> [pr=<n>] <file>@<sha16> <file>@<sha16> ...
#   /snap-diff reject <file> ...            (optional, informational)
#
# or, rejecting only (nothing is committed; the list goes on the PR):
#
#   /snap-diff reject run=<run_id> [pr=<n>] <file> ...
#
# <file> is a `file` from the report's snap_diff_manifest.json; <sha16> is the
# first 16 hex digits of the SHA-256 of its bytes, as the report showed them.
# The bytes come from that run's `*-report-full` artifact and are committed to
# the PR branch at the manifest `path`. Nothing from the repository is
# executed: git only fetches, reads the tree into an index, stages blobs,
# commits and pushes; there is no working tree.
# Stdlib only; shells out to `gh` and `git`.
#
# Environment (all required unless noted):
#   GH_TOKEN             token for gh and git (contents/pull-requests/actions)
#   GITHUB_REPOSITORY    owner/name
#   GITHUB_SERVER_URL    optional, default https://github.com
#   EVENT_NAME           issue_comment (a PR comment) or issues (a new issue)
#   ISSUE_NUMBER         the commented PR, or the new issue
#   BODY                 the comment or issue body: the command
#   AUTHOR               its author's login
#   AUTHOR_ASSOCIATION   pre-filter: OWNER, MEMBER or COLLABORATOR
#   SCREENSHOTS_PATH     optional, default doc/screenshots: every target must be under it
#   CI_WORKFLOW          optional: workflow file to dispatch on the branch after the push
#   RUNNER_TEMP          optional: scratch dir, default a fresh Dir.mktmpdir
#
# The PR is the commented one, or in an issue `pr=`, or else the single open
# same-repository PR on the run's branch. Every refusal is a reply on the
# comment's PR or the issue (then closed as not planned) plus exit status 1;
# a done issue gets a link to the PR and is closed as completed. Replies and
# logs carry only validated strings or fixed text, never raw input.

require "json"
require "open3"
require "base64"
require "digest"
require "fileutils"
require "tmpdir"

module AcceptScreenshots
  class Refusal < StandardError; end

  MAX_FILES = 200
  MAX_BODY = 20_000
  MAX_BYTES = 20 * 1024 * 1024
  MAX_TOTAL_BYTES = 200 * 1024 * 1024
  MAX_ARTIFACT_BYTES = 100 * 1024 * 1024
  MAX_MANIFEST_BYTES = 1024 * 1024
  MAX_CANDIDATES = 10
  ALLOWED_ASSOCIATIONS = %w[OWNER MEMBER COLLABORATOR].freeze
  ALLOWED_CHARS = "only A-Z a-z 0-9 . _ - /, no spaces, no `..`"
  # No spaces: the command is whitespace-split, so a name with one cannot be written.
  SAFE_PATH = %r{\A[A-Za-z0-9._/-]+\z}
  LOGIN = /\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\z/
  FIRST_LINE = %r{\A/snap-diff (?:accept|reject)(?: |\z)}
  HEAD_LINE = %r{\A/snap-diff (accept|reject) run=(\d+)(?: pr=(\d+))?((?: +\S+)*)\z}
  REJECT = %r{\A/snap-diff reject((?: +\S+)*)\z}
  HASHED = /\A([^@]+)@([0-9a-f]{16})\z/
  MAGIC = {".png" => ["PNG", /\A\x89PNG\r\n\x1A\n/n], ".webp" => ["WebP", /\ARIFF....WEBP/mn]}.freeze
  BOT = ["github-actions[bot]", "41898282+github-actions[bot]@users.noreply.github.com"].freeze

  module_function

  # {run:, pr: nil | digits, accept: {file => sha16}, reject: [file]}
  def parse(body)
    raise Refusal, "Comment too long (over #{MAX_BODY} characters)." if body.length > MAX_BODY

    lines = body.lines.map(&:strip).reject(&:empty?)
    unless lines.first&.match?(FIRST_LINE)
      raise Refusal, "The first line must be `/snap-diff accept run=<run id> <file>@<hash> ...` or `/snap-diff reject run=<run id> <file> ...`."
    end

    head = lines.first.match(HEAD_LINE) or raise Refusal, "Missing or invalid `run=<run id>` (digits only)."
    kind, run, pr, rest = head.captures
    tokens = rest.split.uniq
    raise Refusal, "Invalid `pr=<number>` (digits only, right after `run=`)." if tokens.any? { |t| t.start_with?("pr=", "run=") }
    raise Refusal, "The command needs at least one file." if tokens.empty?
    raise Refusal, "Too many files (#{tokens.size}, max #{MAX_FILES})." if tokens.size > MAX_FILES

    reject = (kind == "reject") ? tokens : []
    lines.drop(1).each do |line|
      match = (kind == "accept") && line.match(REJECT) or raise Refusal, "Unexpected line after the first line; only `/snap-diff reject <file> ...` may follow an accept line."
      reject.concat(match[1].split)
    end
    reject.each_with_index { |file, i| raise Refusal, "Rejected file ##{i + 1} is not allowed (#{ALLOWED_CHARS})." unless safe_path?(file) }
    return {run: run, pr: pr, accept: {}, reject: reject.uniq} if kind == "reject"

    files = tokens.each_with_index.with_object({}) do |(token, i), acc|
      match = token.match(HASHED) or raise Refusal, "Accepted file ##{i + 1} lacks its @<hash> (16 lowercase hex); copy the command from the report again."
      file, sha16 = match.captures
      raise Refusal, "Accepted file ##{i + 1} is not allowed (#{ALLOWED_CHARS})." unless safe_path?(file)
      raise Refusal, "`#{file}` is accepted twice with different hashes." if acc.key?(file)

      acc[file] = sha16
    end
    {run: run, pr: pr, accept: files, reject: reject.uniq}
  end

  # A comment acts on the PR it is posted on; a `pr=` in it must agree.
  def comment_pr(command, issue_number)
    raise Refusal, "The command names PR ##{command[:pr]} but was posted on PR ##{issue_number}." if command[:pr] && command[:pr] != issue_number

    issue_number
  end

  # An issue without `pr=`: the single open same-repository PR on the run's branch.
  def resolve_pr(pulls, repo, head_branch)
    matches = pulls.select { |p| p.dig("head", "repo", "full_name") == repo && p.dig("head", "ref") == head_branch }
    raise Refusal, "No open pull request of this repository is on the run's branch." if matches.empty?
    raise Refusal, "More than one open pull request is on the run's branch; add `pr=<number>`." if matches.size > 1

    matches.first["number"].to_s
  end

  # Relative, no empty / `.` / `..` segments, conservative characters.
  def safe_path?(path)
    return false unless path.is_a?(String) && path.match?(SAFE_PATH)

    path.split("/", -1).none? { |segment| segment.empty? || segment == "." || segment == ".." }
  end

  # `permission` is the base role: maintain reads as write, custom roles as their base.
  def writer?(permission_json) = %w[admin write].include?(permission_json["permission"])

  def manifest_entries(manifest)
    entries = manifest.is_a?(Hash) && manifest["entries"]
    (entries.is_a?(Array) && entries.all?(Hash)) ? entries : nil
  end

  # { requested file => target path }, validated.
  def entries_for(manifest, files, screenshots_path)
    entries = manifest_entries(manifest) or raise Refusal, "The report manifest is malformed."

    targets = files.to_h do |file|
      matches = entries.select { |entry| entry["file"] == file }
      raise Refusal, "`#{file}` is not in the report manifest." if matches.empty?
      raise Refusal, "`#{file}` is listed more than once in the report manifest." if matches.size > 1
      raise Refusal, "`#{file}`: only changed or new screenshots can be accepted." unless %w[changed new].include?(matches.first["status"])

      [file, check_target!(file, matches.first["path"], screenshots_path)]
    end
    duplicate = targets.values.tally.find { |_, count| count > 1 }
    raise Refusal, "Two accepted files share the same target `#{duplicate.first}`." if duplicate

    targets
  end

  def check_target!(file, path, screenshots_path)
    allowed = safe_path?(path) && path.start_with?("#{screenshots_path}/") &&
      path.split("/").none? { |segment| segment.downcase.start_with?(".git") }
    raise Refusal, "Target path for `#{file}` is not allowed (under `#{screenshots_path}/`, #{ALLOWED_CHARS}, no `.git*` segment)." unless allowed

    ext = File.extname(path).downcase
    raise Refusal, "`#{file}`: extension must be .png or .webp and match its target." unless MAGIC.key?(ext) && File.extname(file).downcase == ext

    path
  end

  def check_image!(file, bytes)
    kind, magic = MAGIC.fetch(File.extname(file).downcase)
    raise Refusal, "`#{file}` is not a #{kind} image." unless bytes.b.match?(magic)

    nil
  end

  def check_hash!(file, bytes, sha16)
    raise Refusal, "`#{file}` does not match the reviewed hash #{sha16}; review the report again." unless Digest::SHA256.hexdigest(bytes).start_with?(sha16)

    nil
  end

  # Sizes are checked before any byte is read.
  def read_images(dir, files, max_file: MAX_BYTES, max_total: MAX_TOTAL_BYTES)
    root = File.realpath(dir)
    total = 0
    paths = files.to_h do |file|
      path = File.join(dir, file)
      raise Refusal, "`#{file}` is missing from the artifact." unless File.exist?(path) || File.symlink?(path)
      raise Refusal, "`#{file}` in the artifact is not a regular file." unless File.lstat(path).file?
      raise Refusal, "`#{file}` in the artifact is not a regular file." unless File.realpath(path).start_with?("#{root}/")

      size = File.size(path)
      raise Refusal, "`#{file}` is larger than #{max_file} bytes." if size > max_file
      total += size
      raise Refusal, "The accepted files together are larger than #{max_total} bytes." if total > max_total

      [file, path]
    end
    paths.transform_values { |path| File.binread(path) }
  end

  # Report artifact names, sorted; expired and oversized ones left out.
  def report_artifacts(artifacts_json)
    artifacts_json.fetch("artifacts")
      .select { |a| !a["expired"] && a["name"].to_s.end_with?("-report-full") && a["size_in_bytes"].to_i <= MAX_ARTIFACT_BYTES }
      .map { |a| a["name"] }.sort
  end

  # The first of at most MAX_CANDIDATES artifacts whose manifest lists every
  # file with the command's hash: [index, manifest]. The block loads one
  # manifest (index, name), so later artifacts are never downloaded. The
  # manifest is only a pointer; the gate is check_hash! on the picked bytes.
  def pick_artifact(names, accept)
    names.first(MAX_CANDIDATES).each_with_index do |name, i|
      manifest = yield(name, i)
      entries = manifest_entries(manifest) or next
      covered = accept.all? { |file, sha16| entries.any? { |e| e["file"] == file && e["sha256"].to_s.start_with?(sha16) } }
      return [i, manifest] if covered
    end
    raise Refusal, "No report artifact of this run lists all of #{accept.keys.join(", ")} with those hashes."
  end

  def load_manifest(dir)
    path = File.join(dir, "snap_diff_manifest.json")
    return unless File.file?(path) && !File.symlink?(path) && File.size(path) <= MAX_MANIFEST_BYTES

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    nil
  end

  # The run must come from this repository (no forks) and from this PR: a run
  # of another PR or event on the same commit carries another report. A
  # workflow_dispatch run (this bot's CI re-dispatch) lists no PRs, so it
  # counts when it ran on the PR's branch. head_sha equality is checked apart.
  def check_run!(run, repo, pr, run_id, head_ref)
    raise Refusal, "Run #{run_id} was not built from this repository." unless run.dig("head_repository", "full_name") == repo

    of_pr = Array(run["pull_requests"]).any? { |p| p["number"].to_s == pr }
    dispatched_on_branch = run["event"] == "workflow_dispatch" && run["head_branch"] == head_ref
    raise Refusal, "Run #{run_id} is not a run of this pull request." unless of_pr || dispatched_on_branch

    nil
  end

  # Paths whose `git check-attr filter` output says lfs.
  def lfs_paths(check_attr_output)
    check_attr_output.lines.filter_map do |line|
      path, value = line.chomp.split(": filter: ", 2)
      path if value == "lfs"
    end
  end

  def summary(command, targets, sha, ci_line)
    lines = [sha ? "Accepted #{targets.size} screenshot(s) from run #{command[:run]} in #{sha}:" :
      "Nothing to commit: these screenshots from run #{command[:run]} already match the PR branch:"]
    targets.each { |file, path| lines << "- `#{file}` -> `#{path}`" }
    unless command[:reject].empty?
      lines << "" << "Rejected (not committed):"
      command[:reject].each { |file| lines << "- `#{file}`" }
    end
    lines << "" << ci_line if sha
    lines.join("\n")
  end

  def reject_summary(command)
    (["Rejected in run #{command[:run]} (not committed):"] + command[:reject].map { |file| "- `#{file}`" }).join("\n")
  end

  def commit_message(targets, run_id, login, pr)
    bullets = targets.map { |file, path| "- #{file} -> #{path}" }.join("\n")
    "Accept screenshot baselines\n\nAccepted by @#{login} in PR ##{pr} from run #{run_id}:\n#{bullets}\n"
  end

  # Workflow commands start a line with `::`; nothing logged may.
  # A lone \r ends a line for the runner too.
  def log_text(text) = text.to_s[0, 4000].gsub(/\r\n?/, "\n").gsub(/^(\s*)::/, '\1: :')

  def log(text) = warn(log_text(text))

  # ---- side effects ---------------------------------------------------------

  def env(name) = ENV.fetch(name) { abort "#{name} is not set" }

  def sh(*cmd, stdin: nil, env: {}, chdir: nil)
    opts = {stdin_data: stdin, binmode: true}
    opts[:chdir] = chdir if chdir
    out, err, status = Open3.capture3(env, *cmd, **opts)
    log(err) unless err.empty?
    [out, status.success?]
  end

  def sh!(*cmd, **opts)
    out, ok = sh(*cmd, **opts)
    raise "#{cmd.first(2).join(" ")} failed" unless ok

    out
  end

  def gh_json(path) = JSON.parse(sh!("gh", "api", path))

  def reply(repo, number, text)
    sh!("gh", "api", "-X", "POST", "repos/#{repo}/issues/#{number}/comments", "--input", "-", stdin: JSON.generate(body: text))
  end

  def close_issue(repo, number, reason)
    sh!("gh", "api", "-X", "PATCH", "repos/#{repo}/issues/#{number}", "--input", "-", stdin: JSON.generate(state: "closed", state_reason: reason))
  end

  # A fresh, isolated git: no global or system config, no hooks, no LFS
  # downloads, the bot as author. `auth` adds the token as an HTTP header via
  # GIT_CONFIG_* env -- never argv, a remote URL or .git/config.
  def git_env(auth = nil)
    config = [["core.hooksPath", "/dev/null"]]
    config << ["http.#{ENV.fetch("GITHUB_SERVER_URL", "https://github.com")}/.extraheader", "AUTHORIZATION: basic #{auth}"] if auth
    vars = {
      "GIT_CONFIG_GLOBAL" => "/dev/null", "GIT_CONFIG_NOSYSTEM" => "1",
      "GIT_LFS_SKIP_SMUDGE" => "1", "GIT_TERMINAL_PROMPT" => "0",
      "GIT_AUTHOR_NAME" => BOT[0], "GIT_AUTHOR_EMAIL" => BOT[1],
      "GIT_COMMITTER_NAME" => BOT[0], "GIT_COMMITTER_EMAIL" => BOT[1],
      "GIT_CONFIG_COUNT" => config.size.to_s
    }
    config.each_with_index { |(key, value), i| vars.merge!("GIT_CONFIG_KEY_#{i}" => key, "GIT_CONFIG_VALUE_#{i}" => value) }
    vars
  end

  def run!
    repo = env("GITHUB_REPOSITORY")
    issue = env("ISSUE_NUMBER")
    raise "ISSUE_NUMBER is not a number" unless issue.match?(/\A\d+\z/)
    issue_mode = {"issues" => true, "issue_comment" => false}.fetch(env("EVENT_NAME"))

    exit 1 unless accept!(repo, issue, issue_mode)
  rescue Refusal => e
    log(e.message)
    reply(repo, issue, "Screenshot accept refused: #{e.message}")
    close_issue(repo, issue, "not_planned") if issue_mode
    exit 1
  rescue => e
    log("#{e.class}: #{e.message}")
    reply(repo, issue, "Screenshot accept failed; see the workflow log.") if repo && issue
    exit 1
  end

  # True unless the commit landed but the CI dispatch failed.
  def accept!(repo, issue, issue_mode)
    raise Refusal, "Only owners, members and collaborators can accept screenshots." unless ALLOWED_ASSOCIATIONS.include?(env("AUTHOR_ASSOCIATION"))

    login = env("AUTHOR")
    raise Refusal, "Only people with write access can accept screenshots." unless login.match?(LOGIN)
    # MEMBER/COLLABORATOR includes read-only people; the permission API does not.
    raise Refusal, "Only people with write access can accept screenshots." unless writer?(gh_json("repos/#{repo}/collaborators/#{login}/permission"))

    screenshots_path = ENV.fetch("SCREENSHOTS_PATH", "doc/screenshots").delete_suffix("/")
    raise "SCREENSHOTS_PATH must be a safe relative path" unless safe_path?(screenshots_path)
    workflow = ENV["CI_WORKFLOW"].to_s
    raise "CI_WORKFLOW must be a workflow file name" unless workflow.empty? || workflow.match?(/\A[\w.-]+\.ya?ml\z/)

    command = parse(env("BODY"))
    run_id = command[:run]
    files = command[:accept].keys

    run = gh_json("repos/#{repo}/actions/runs/#{run_id}")
    pr = if !issue_mode then comment_pr(command, issue)
    elsif command[:pr] then command[:pr]
    else
      raise Refusal, "Run #{run_id} has no branch; add `pr=<number>`." unless run["head_branch"].is_a?(String)

      pulls = sh!("gh", "api", "-X", "GET", "repos/#{repo}/pulls", "-f", "state=open", "-f", "per_page=100",
        "-f", "head=#{repo.split("/").first}:#{run["head_branch"]}")
      resolve_pr(JSON.parse(pulls), repo, run["head_branch"])
    end
    pull = gh_json("repos/#{repo}/pulls/#{pr}")
    branch = pull.dig("head", "ref")
    check_run!(run, repo, pr, run_id, branch)
    raise Refusal, "The pull request is not open." unless pull["state"] == "open"
    return finish(repo, issue, issue_mode, pr, reject_summary(command), "Recorded on PR ##{pr}.") if files.empty?

    raise Refusal, "The pull request comes from a fork." unless pull.dig("head", "repo", "full_name") == repo
    raise Refusal, "PR has new commits since run #{run_id} — review the new report." unless pull.dig("head", "sha") == run["head_sha"]
    raise "unexpected head_sha" unless run["head_sha"].to_s.match?(/\A\h{40}\z/)
    raise Refusal, "Refusing to push to the base or default branch." if [pull.dig("base", "ref"), pull.dig("base", "repo", "default_branch")].include?(branch)

    work = Dir.mktmpdir("snap-diff-accept-", ENV["RUNNER_TEMP"] || Dir.mktmpdir)
    names = report_artifacts(gh_json("repos/#{repo}/actions/runs/#{run_id}/artifacts?per_page=100"))
    picked, manifest = pick_artifact(names, command[:accept]) do |name, i|
      dir = File.join(work, "artifact-#{i}")
      sh!("gh", "run", "download", run_id, "-R", repo, "-n", name, "-D", dir)
      load_manifest(dir)
    end
    targets = entries_for(manifest, files, screenshots_path)
    images = read_images(File.join(work, "artifact-#{picked}"), files)
    images.each do |file, bytes|
      check_image!(file, bytes)
      check_hash!(file, bytes, command[:accept].fetch(file))
    end

    auth = Base64.strict_encode64("x-access-token:#{env("GH_TOKEN")}")
    puts "::add-mask::#{auth}" if ENV["GITHUB_ACTIONS"] == "true"
    sha = commit_and_push(remote: "#{ENV.fetch("GITHUB_SERVER_URL", "https://github.com")}/#{repo}.git", head_sha: run["head_sha"],
      branch: branch, targets: targets, images: images, dir: File.join(work, "repo"),
      message: commit_message(targets, run_id, login, pr), git_env: git_env(auth))

    ci_line = workflow.empty? ? "Re-run CI to verify." : "Dispatching `#{workflow}` on the PR branch to verify."
    finish(repo, issue, issue_mode, pr, summary(command, targets, sha, ci_line), "Applied to PR ##{pr}: #{sha || "nothing to commit"}.")
    puts "accepted #{targets.size} file(s): #{sha || "no change"}"
    return true unless sha && !workflow.empty?

    dispatch_ci(repo, pr, workflow, branch)
  ensure
    FileUtils.rm_rf(work) if work # nothing of this run outlives it on a persistent runner
  end

  # The outcome goes on the PR; an issue also gets a link to it and is closed.
  def finish(repo, issue, issue_mode, pr, pr_text, issue_text)
    reply(repo, pr, pr_text)
    return true unless issue_mode

    reply(repo, issue, issue_text)
    close_issue(repo, issue, "completed")
    true
  end

  # Best effort, after the reply: a failure must not hide the pushed commit.
  # A push made with GITHUB_TOKEN does not start workflows; a
  # workflow_dispatch made with it does.
  def dispatch_ci(repo, pr, workflow, branch)
    _, ok = sh("gh", "workflow", "run", workflow, "-R", repo, "--ref", branch)
    return true if ok

    log("CI dispatch failed; the commit is pushed.")
    reply(repo, pr, "The commit is pushed, but dispatching `#{workflow}` failed. Re-run CI to verify.")
    false
  end

  # A scratch repository holding only the reviewed commit, read into the
  # index; no working tree. Blobs are written from the verified bytes with
  # --no-filters and staged by id, so the PR's .gitattributes cannot rewrite
  # them.
  # Returns the pushed commit, or nil when the bytes are already committed.
  def commit_and_push(remote:, head_sha:, branch:, targets:, images:, dir:, message:, git_env:)
    git = ->(*args, stdin: nil) { sh!("git", *args, stdin: stdin, env: git_env, chdir: dir) }

    FileUtils.mkdir_p(dir)
    git.call("init", "-q")
    git.call("remote", "add", "origin", remote)
    git.call("fetch", "-q", "--depth=1", "origin", head_sha)
    git.call("read-tree", head_sha)

    lfs = lfs_paths(git.call("check-attr", "--cached", "filter", "--", *targets.values))
    raise Refusal, lfs.map { |path| "`#{path}` is tracked by Git LFS; accept it locally." }.join(" ") unless lfs.empty?

    targets.each do |file, path|
      bytes = images.fetch(file)
      blob = git.call("hash-object", "-w", "--no-filters", "--stdin", stdin: bytes).strip
      raise "staged blob differs from the verified bytes" unless blob == Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes.b)

      git.call("update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}")
    end
    _, unchanged = sh("git", "diff-index", "--cached", "--quiet", head_sha, env: git_env, chdir: dir)
    return nil if unchanged

    commit = git.call("commit-tree", git.call("write-tree").strip, "-p", head_sha, "-F", "-", stdin: message).strip
    # A lease, not a force: the push lands only while the branch is exactly the
    # reviewed head_sha. A plain push would still fast-forward a branch reset
    # to an ancestor of head_sha and bring the removed commits back.
    _, pushed = sh("git", "push", "-q", "--force-with-lease=refs/heads/#{branch}:#{head_sha}", "origin", "#{commit}:refs/heads/#{branch}", env: git_env, chdir: dir)
    raise Refusal, "Push rejected: the branch moved or is protected. Review the new report." unless pushed

    commit
  end
end

AcceptScreenshots.run! if $PROGRAM_NAME == __FILE__
