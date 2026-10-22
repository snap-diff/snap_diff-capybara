# frozen_string_literal: true

require "test_helper"
require "support/fake_github_api"

class ReviewPageCspTest < Minitest::Test
  def test_csp_script_hash_matches_the_inline_script
    html = FakeGithub::PAGE.read

    assert_equal 1, html.scan(/<script\b/).size, "the page must have exactly one inline script"
    declared = html[/<meta http-equiv="Content-Security-Policy" content="[^"]*script-src '(sha256-[^']+)'/, 1]
    refute_nil declared, "the CSP meta has no script-src 'sha256-...'"
    actual = FakeGithub.script_sha256(html)

    assert_equal actual, declared, <<~MSG
      The CSP script hash in lib/snap_diff/review/index.html is stale (the browser would refuse to run the page).
      Recompute it: take the exact text between <script> and </script> and run
        ruby -rdigest -e 'puts "sha256-" + [Digest::SHA256.digest(File.read("lib/snap_diff/review/index.html")[%r{<script>(.*?)</script>}m, 1])].pack("m0")'
      then paste the result into the meta's script-src.
    MSG
  end
end
