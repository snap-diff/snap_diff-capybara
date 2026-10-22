# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require_relative "../../.github/actions/accept-screenshots/accept_screenshots"

class AcceptScreenshotsTest < Minitest::Test
  A = AcceptScreenshots
  PNG = "\x89PNG\r\n\x1A\n".b + "rest\r\n".b
  WEBP = "RIFF\x10\x00\x00\x00WEBPVP8 ".b
  HOSTILE = "x\n::add-mask::s @someone [a](http://e)"

  def refusal(&block) = assert_raises(A::Refusal, &block).message

  def sha16(bytes) = Digest::SHA256.hexdigest(bytes)[0, 16]

  def assert_not_echoed(text)
    %w[add-mask @someone http:// [a]].each { |bit| refute_includes text, bit }
  end

  # -- parse --------------------------------------------------------------

  def test_parse_accept_and_reject
    body = "/snap-diff accept run=123 linux/a.png@0123abcd0123abcd linux/b.webp@ffffffffffffffff\r\n/snap-diff reject linux/c.png\n"

    assert_equal({run: "123", pr: nil, accept: {"linux/a.png" => "0123abcd0123abcd", "linux/b.webp" => "ffffffffffffffff"}, reject: %w[linux/c.png]}, A.parse(body))
  end

  def test_parse_without_reject_line
    assert_equal({run: "7", pr: nil, accept: {"a.png" => "0123abcd0123abcd"}, reject: []}, A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd"))
  end

  def test_parse_pr
    assert_equal({run: "7", pr: "12", accept: {"a.png" => "0123abcd0123abcd"}, reject: %w[b.png]},
      A.parse("/snap-diff accept run=7 pr=12 a.png@0123abcd0123abcd\n/snap-diff reject b.png"))
    assert_match(/pr=/, refusal { A.parse("/snap-diff accept run=7 pr=x a.png@0123abcd0123abcd") })
  end

  def test_parse_reject_only
    assert_equal({run: "7", pr: "12", accept: {}, reject: %w[a.png b.png]}, A.parse("/snap-diff reject run=7 pr=12 a.png b.png"))
    assert_equal({run: "7", pr: nil, accept: {}, reject: %w[a.png]}, A.parse("/snap-diff reject run=7 a.png"))
  end

  def test_parse_refuses_reject_only_without_run_or_files
    assert_match(/run=/, refusal { A.parse("/snap-diff reject a.png") })
    assert_match(/at least one file/, refusal { A.parse("/snap-diff reject run=7") })
    assert_match(/unexpected line/i, refusal { A.parse("/snap-diff reject run=7 a.png\n/snap-diff reject b.png") })
  end

  def test_parse_drops_duplicate_files
    assert_equal({"a.png" => "0123abcd0123abcd"}, A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd a.png@0123abcd0123abcd")[:accept])
  end

  def test_parse_refuses_one_file_with_two_hashes
    assert_match(/twice/, refusal { A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd a.png@0000000000000000") })
  end

  def test_parse_requires_the_hash
    ["a.png", "a.png@0123abcd", "a.png@0123abcd0123abc", "a.png@0123ABCD0123ABCD", "a.png@0123abcd0123abcd0", "a.png@"].each do |token|
      assert_match(/@<hash>/, refusal { A.parse("/snap-diff accept run=7 #{token}") }, token)
    end
  end

  def test_parse_refuses_missing_run
    assert_match(/run=/, refusal { A.parse("/snap-diff accept a.png@0123abcd0123abcd") })
    assert_match(/run=/, refusal { A.parse("/snap-diff accept run=12x a.png@0123abcd0123abcd") })
  end

  def test_parse_refuses_no_files
    assert_match(/at least one file/, refusal { A.parse("/snap-diff accept run=7") })
  end

  def test_parse_refuses_other_lines
    assert_match(/unexpected line/i, refusal { A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd\nplease merge") })
    assert_match(/first line/, refusal { A.parse("hi\n/snap-diff accept run=7 a.png@0123abcd0123abcd") })
  end

  def test_parse_refuses_bad_chars_without_echoing_them
    assert_match(/not allowed/, refusal { A.parse("/snap-diff accept run=7 a$(id).png@0123abcd0123abcd") })
    assert_match(/not allowed/, refusal { A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd\n/snap-diff reject b;c.png") })
    assert_not_echoed refusal { A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd\n/snap-diff reject [a](http://e)@someone") }
  end

  def test_parse_refuses_dot_dot_and_absolute
    ["../a.png", "x/../../a.png", "/etc/a.png"].each do |file|
      assert_match(/not allowed/, refusal { A.parse("/snap-diff accept run=7 #{file}@0123abcd0123abcd") }, file)
    end
  end

  def test_parse_refuses_too_many_files
    files = (1..A::MAX_FILES + 1).map { |i| "f#{i}.png@0123abcd0123abcd" }.join(" ")

    assert_match(/too many/i, refusal { A.parse("/snap-diff accept run=7 #{files}") })
  end

  def test_parse_refuses_long_comment
    assert_match(/too long/, refusal { A.parse("/snap-diff accept run=7 a.png@0123abcd0123abcd" + " " * A::MAX_BODY) })
  end

  # -- safe_path? -----------------------------------------------------------

  def test_safe_path
    assert A.safe_path?("test/fixtures/app/doc/screenshots/linux/index.png")
    refute A.safe_path?("with space/x.png")
    refute A.safe_path?("")
    refute A.safe_path?("a/./b.png")
    refute A.safe_path?("a//b.png")
    refute A.safe_path?("a\nb.png")
    refute A.safe_path?("a@b.png")
  end

  # -- writer? ----------------------------------------------------------------

  def test_writer
    assert A.writer?({"permission" => "admin", "role_name" => "admin"})
    assert A.writer?({"permission" => "write", "role_name" => "maintain"})
    assert A.writer?({"permission" => "write", "role_name" => "write"})
    assert A.writer?({"permission" => "write", "role_name" => "custom-writer"})
    refute A.writer?({"permission" => "read", "role_name" => "write"}), "the base permission decides"
    refute A.writer?({"permission" => "read", "role_name" => "triage"})
    refute A.writer?({"permission" => "read", "role_name" => "read"})
    refute A.writer?({"permission" => "none"})
  end

  # -- entries_for: manifest lookup ----------------------------------------

  def manifest(*entries) = {"version" => 1, "entries" => entries}

  def entry(file, path: "shots/#{file}", status: "changed", sha256: "0" * 64)
    {"name" => file, "status" => status, "path" => path, "file" => file, "sha256" => sha256}
  end

  def test_entries_for_maps_file_to_path
    m = manifest(entry("a.png"), entry("b.webp", status: "new"), entry("c.png"))

    assert_equal({"a.png" => "shots/a.png", "b.webp" => "shots/b.webp"}, A.entries_for(m, %w[a.png b.webp], "shots"))
  end

  def test_entries_for_refuses_unlisted_file
    assert_match(/not in the report/, refusal { A.entries_for(manifest(entry("a.png")), %w[b.png], "shots") })
  end

  def test_entries_for_refuses_status_without_echoing_it
    message = refusal { A.entries_for(manifest(entry("a.png", status: HOSTILE)), %w[a.png], "shots") }

    assert_match(/only changed or new/, message)
    assert_not_echoed message
  end

  def test_entries_for_refuses_target_outside_screenshots_path
    ["other/a.png", "shotsy/a.png", "shots.png"].each do |path|
      assert_match(/not allowed/, refusal { A.entries_for(manifest(entry("a.png", path: path)), %w[a.png], "shots") }, path)
    end
  end

  def test_entries_for_refuses_git_segments
    ["shots/.git/x.png", "shots/.GIT/x.png", "shots/.github/x.png", "shots/.gitattributes/x.png"].each do |path|
      assert_match(/not allowed/, refusal { A.entries_for(manifest(entry("a.png", path: path)), %w[a.png], "shots") }, path)
    end
  end

  def test_entries_for_refuses_unsafe_target_without_echoing_it
    ["shots/../a.png", "/shots/a.png", "shots/a;b.png", "shots/with space.png", HOSTILE].each do |path|
      message = refusal { A.entries_for(manifest(entry("a.png", path: path)), %w[a.png], "shots") }
      assert_match(/not allowed/, message, path)
      assert_not_echoed message
    end
  end

  def test_entries_for_refuses_extension_mismatch
    assert_match(/extension/, refusal { A.entries_for(manifest(entry("a.png", path: "shots/a.webp")), %w[a.png], "shots") })
    assert_match(/extension/, refusal { A.entries_for(manifest(entry("a.txt")), %w[a.txt], "shots") })
  end

  def test_entries_for_refuses_two_files_one_target
    m = manifest(entry("a.png", path: "shots/x.png"), entry("b.png", path: "shots/x.png"))

    assert_match(/same target/, refusal { A.entries_for(m, %w[a.png b.png], "shots") })
  end

  def test_entries_for_refuses_duplicate_manifest_file
    assert_match(/more than once/, refusal { A.entries_for(manifest(entry("a.png"), entry("a.png")), %w[a.png], "shots") })
  end

  def test_entries_for_refuses_malformed_manifest
    assert_match(/manifest/, refusal { A.entries_for({"entries" => "x"}, %w[a.png], "shots") })
    assert_match(/manifest/, refusal { A.entries_for(nil, %w[a.png], "shots") })
  end

  # -- check_image! / check_hash! -----------------------------------------------

  def test_check_image_accepts_png_and_webp
    assert_nil A.check_image!("a.png", PNG)
    assert_nil A.check_image!("a.webp", WEBP)
  end

  def test_check_image_refuses_wrong_magic
    assert_match(/not a PNG/, refusal { A.check_image!("a.png", WEBP) })
    assert_match(/not a WebP/, refusal { A.check_image!("a.webp", PNG) })
    assert_match(/not a PNG/, refusal { A.check_image!("a.png", "#!/bin/sh") })
  end

  def test_check_hash
    assert_nil A.check_hash!("a.png", PNG, sha16(PNG))
    assert_match(/does not match/, refusal { A.check_hash!("a.png", PNG + "x", sha16(PNG)) })
  end

  # -- read_images: sizes before reading ----------------------------------------

  def test_read_images_checks_sizes_before_reading
    Dir.mktmpdir do |dir|
      File.binwrite(File.join(dir, "a.png"), PNG)
      File.binwrite(File.join(dir, "b.png"), PNG)

      assert_equal({"a.png" => PNG}, A.read_images(dir, %w[a.png]))
      assert_match(/larger/, refusal { A.read_images(dir, %w[a.png], max_file: PNG.bytesize - 1) })
      assert_match(/together/, refusal { A.read_images(dir, %w[a.png b.png], max_total: PNG.bytesize * 2 - 1) })
    end
  end

  def test_read_images_refuses_symlinks_and_missing_files
    Dir.mktmpdir do |dir|
      File.symlink("/etc/hosts", File.join(dir, "a.png"))

      assert_match(/not a regular file/, refusal { A.read_images(dir, %w[a.png]) })
      assert_match(/missing/, refusal { A.read_images(dir, %w[b.png]) })
    end
  end

  # -- artifacts ------------------------------------------------------------------

  def test_report_artifacts_keeps_unexpired_report_artifacts_under_the_cap
    artifacts = {"artifacts" => [
      {"name" => "z-report-full", "expired" => false, "size_in_bytes" => 10},
      {"name" => "a-report-full", "expired" => false, "size_in_bytes" => 10},
      {"name" => "huge-report-full", "expired" => false, "size_in_bytes" => A::MAX_ARTIFACT_BYTES + 1},
      {"name" => "a-diffs", "expired" => false, "size_in_bytes" => 10},
      {"name" => "old-report-full", "expired" => true, "size_in_bytes" => 10}
    ]}

    assert_equal %w[a-report-full z-report-full], A.report_artifacts(artifacts)
  end

  def accept(*files) = files.to_h { |file| [file, "0" * 16] }

  def test_pick_artifact_takes_the_first_manifest_listing_every_file_with_its_hash_and_stops_there
    manifests = [
      manifest(entry("x.png")),
      manifest(entry("x.png"), entry("y.png", sha256: "f" * 64)), # y.png: another hash
      manifest(entry("x.png"), entry("y.png")),
      manifest(entry("x.png"), entry("y.png"))
    ]
    loaded = []

    picked = A.pick_artifact(%w[a b c d], accept("x.png", "y.png")) do |name, i|
      loaded << name
      manifests[i]
    end

    assert_equal [2, manifests[2]], picked
    assert_equal %w[a b c], loaded, "stops downloading once one covers"
  end

  def test_pick_artifact_refuses_when_none_covers
    assert_match(/No report artifact/, refusal { A.pick_artifact(%w[a b], accept("x.png")) { |_, i| [manifest(entry("y.png")), nil][i] } })
    assert_match(/No report artifact/, refusal { A.pick_artifact([], accept("x.png")) { flunk } })
  end

  def test_pick_artifact_tries_at_most_ten_candidates
    loaded = []
    names = (1..12).map(&:to_s)

    refusal { A.pick_artifact(names, accept("x.png")) { |name| (loaded << name) && nil } }

    assert_equal names.first(A::MAX_CANDIDATES), loaded
  end

  def test_load_manifest_refuses_oversized_or_missing_files
    Dir.mktmpdir do |dir|
      assert_nil A.load_manifest(dir)
      File.write(File.join(dir, "snap_diff_manifest.json"), JSON.generate(manifest(entry("x.png"))))
      assert_equal manifest(entry("x.png")), A.load_manifest(dir)
      File.write(File.join(dir, "snap_diff_manifest.json"), " " * (A::MAX_MANIFEST_BYTES + 1))
      assert_nil A.load_manifest(dir)
    end
  end

  # -- check_run! -----------------------------------------------------------

  def run_json(repo: "o/r", prs: [5], event: "pull_request", branch: "feat")
    {"head_repository" => {"full_name" => repo}, "pull_requests" => prs.map { |n| {"number" => n} },
     "event" => event, "head_branch" => branch}
  end

  def test_check_run_accepts_this_repo_and_pr
    assert_nil A.check_run!(run_json, "o/r", "5", "9", "feat")
  end

  def test_check_run_accepts_dispatch_on_the_pr_branch
    assert_nil A.check_run!(run_json(prs: [], event: "workflow_dispatch"), "o/r", "5", "9", "feat")
  end

  def test_check_run_refuses_fork
    assert_match(/not built from this repository/, refusal { A.check_run!(run_json(repo: "fork/r"), "o/r", "5", "9", "feat") })
  end

  def test_check_run_refuses_run_of_another_pr
    assert_match(/not a run of this pull request/, refusal { A.check_run!(run_json(prs: [6]), "o/r", "5", "9", "feat") })
    assert_match(/not a run of this pull request/, refusal { A.check_run!(run_json(prs: []), "o/r", "5", "9", "feat") })
  end

  def test_check_run_refuses_dispatch_on_another_branch
    run = run_json(prs: [], event: "workflow_dispatch", branch: "other")

    assert_match(/not a run of this pull request/, refusal { A.check_run!(run, "o/r", "5", "9", "feat") })
  end

  def test_check_run_refuses_push_run_of_another_branch_same_sha
    run = run_json(prs: [], event: "push", branch: "other")

    assert_match(/not a run of this pull request/, refusal { A.check_run!(run, "o/r", "5", "9", "feat") })
  end

  # -- which pull request ------------------------------------------------------

  def pull(number, repo: "o/r", ref: "feat") = {"number" => number, "head" => {"ref" => ref, "repo" => {"full_name" => repo}}}

  def test_resolve_pr_takes_the_single_open_same_repo_pr_on_the_branch
    pulls = [pull(3), pull(4, repo: "fork/r"), pull(5, ref: "other")]

    assert_equal "3", A.resolve_pr(pulls, "o/r", "feat")
  end

  def test_resolve_pr_refuses_none_or_several
    assert_match(/No open pull request/, refusal { A.resolve_pr([pull(4, repo: "fork/r")], "o/r", "feat") })
    assert_match(/More than one/, refusal { A.resolve_pr([pull(3), pull(6)], "o/r", "feat") })
  end

  def test_comment_pr_is_the_commented_pr
    assert_equal "5", A.comment_pr({pr: nil}, "5")
    assert_equal "5", A.comment_pr({pr: "5"}, "5")
    assert_match(/names PR #6 but was posted on PR #5/, refusal { A.comment_pr({pr: "6"}, "5") })
  end

  # -- text that reaches replies and logs -------------------------------------

  def test_reject_summary
    text = A.reject_summary({run: "7", accept: {}, reject: %w[a.png b.png]})

    assert_includes text, "run 7"
    assert_includes text, "- `a.png`\n- `b.png`"
  end

  def test_lfs_paths
    out = "a/x.png: filter: lfs\nc.png: filter: unspecified\nd.webp: filter: other\n"

    assert_equal ["a/x.png"], A.lfs_paths(out)
  end

  def test_log_text_neutralises_workflow_commands
    text = A.log_text("ok\n::add-mask::secret\n  ::error::x\r::warning::y")

    refute_match(/(\A|[\r\n])\s*::/, text) # a lone \r starts a line for the runner too
    assert_includes text, "ok"
  end

  def test_summary_names_only_validated_strings
    command = {run: "7", accept: {"a.png" => "0123abcd0123abcd"}, reject: %w[b.png]}
    text = A.summary(command, {"a.png" => "shots/a.png"}, "f" * 40, "Re-run CI to verify.")

    assert_includes text, "`a.png` -> `shots/a.png`"
    assert_includes text, "`b.png`"
    assert_includes text, "f" * 40
  end

  def test_commit_message_credits_the_commenter_in_the_body
    message = A.commit_message({"a.png" => "shots/a.png"}, "7", "octo-cat", "5")

    assert_equal "Accept screenshot baselines", message.lines.first.chomp
    assert_includes message, "Accepted by @octo-cat in PR #5"
    refute_includes message, "Co-authored-by"
  end

  # -- commit_and_push against a local bare repository --------------------------

  def git(dir, *args, env: A.git_env) = A.sh!("git", *args, env: env, chdir: dir).strip

  # A bare remote whose feat branch has two commits; the second is the reviewed head.
  def with_remote(attributes: "")
    Dir.mktmpdir do |root|
      remote = File.join(root, "remote.git")
      seed = File.join(root, "seed")
      git(root, "init", "-q", "--bare", remote)
      git(remote, "config", "receive.shallowUpdate", "true") # as GitHub: a push from the shallow clone lands
      git(root, "init", "-q", seed)
      File.write(File.join(seed, ".gitattributes"), attributes)
      FileUtils.mkdir_p(File.join(seed, "shots"))
      File.binwrite(File.join(seed, "shots/a.png"), "old")
      git(seed, "add", ".")
      git(seed, "commit", "-q", "-m", "one")
      ancestor = git(seed, "rev-parse", "HEAD")
      git(seed, "commit", "-q", "--allow-empty", "-m", "two")
      head = git(seed, "rev-parse", "HEAD")
      git(seed, "push", "-q", remote, "HEAD:refs/heads/feat")
      yield remote, head, ancestor, File.join(root, "work")
    end
  end

  def push(remote, head, dir, targets: {"a.png" => "shots/a.png"}, images: {"a.png" => PNG})
    A.commit_and_push(remote: remote, head_sha: head, branch: "feat", targets: targets, images: images,
      dir: dir, message: "Accept screenshot baselines\n", git_env: A.git_env)
  end

  def test_committed_bytes_equal_the_artifact_bytes_despite_text_attributes
    with_remote(attributes: "*.png text eol=lf\n") do |remote, head, _, dir|
      sha = push(remote, head, dir)

      assert_equal sha, git(remote, "rev-parse", "feat")
      assert_equal PNG, A.sh!("git", "cat-file", "blob", "feat:shots/a.png", env: A.git_env, chdir: remote).b
    end
  end

  def test_nothing_to_commit_when_bytes_already_match
    with_remote do |remote, head, _, dir|
      assert_nil push(remote, head, dir, images: {"a.png" => "old".b})
      assert_equal head, git(remote, "rev-parse", "feat")
    end
  end

  def test_a_moved_branch_rejects_the_push
    with_remote do |remote, head, ancestor, dir|
      git(remote, "update-ref", "refs/heads/feat", ancestor) # reset to an ancestor: a plain push would fast-forward

      assert_match(/Push rejected: the branch moved or is protected/, refusal { push(remote, head, dir) })
      assert_equal ancestor, git(remote, "rev-parse", "feat")
    end
  end

  # The shallow clone alone already refuses the ancestor case above ("fetch
  # first"); only the lease refuses recreating a branch deleted after review.
  def test_a_deleted_branch_is_not_recreated
    with_remote do |remote, head, _, dir|
      git(remote, "update-ref", "-d", "refs/heads/feat")

      assert_match(/Push rejected/, refusal { push(remote, head, dir) })
      refute_includes git(remote, "branch", "--list"), "feat"
    end
  end

  def test_lfs_tracked_target_is_refused
    with_remote(attributes: "*.png filter=lfs\n") do |remote, head, _, dir|
      assert_match(/Git LFS/, refusal { push(remote, head, dir) })
    end
  end
end
