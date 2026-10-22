# frozen_string_literal: true

require "digest"
require "json"
require "rack"
require "zlib"

# Serves the review page (rewritten to talk to itself) and a fake GitHub REST
# API from one Rack app, and records every API request it sees.
class FakeGithub
  PAGE = Pathname.new(File.expand_path("../../lib/snap_diff/review/index.html", __dir__))
  HEAD_SHA = "a1" * 20
  Request = Struct.new(:method, :path, :query, :authorization, :json)

  # The exact text between <script> and </script>; the CSP hashes it.
  def self.script_sha256(html)
    "sha256-#{[Digest::SHA256.digest(html[%r{<script>(.*?)</script>}m, 1])].pack("m0")}"
  end

  # A stored-or-deflated zip with just what the page's reader needs.
  def self.zip(files)
    out = +"".b
    central = +"".b
    files.each do |name, bytes|
      bytes = bytes.b
      deflater = Zlib::Deflate.new(Zlib::DEFAULT_COMPRESSION, -Zlib::MAX_WBITS)
      packed = deflater.deflate(bytes, Zlib::FINISH)
      crc = Zlib.crc32(bytes)
      fields = [20, 0, 8, 0, 0, crc, packed.bytesize, bytes.bytesize, name.bytesize, 0]
      central << [0x02014b50, 20].pack("Vv") << fields.pack("vvvvvVVVvv") << [0, 0, 0, 0, out.bytesize].pack("vvvVV") << name.b
      out << [0x04034b50].pack("V") << fields.pack("vvvvvVVVvv") << name.b << packed
    end
    out << central << [0x06054b50, 0, 0, files.size, files.size, central.bytesize, out.bytesize - central.bytesize, 0].pack("VvvvvVVv")
  end

  attr_reader :requests
  attr_accessor :run, :artifact, :pull, :zip, :baselines, :runs_status, :patch_status, :moved_ref_sha

  def initialize(zip:, baselines: {})
    @zip = zip
    @baselines = baselines
    @requests = []
    @run = {id: 11, head_sha: HEAD_SHA, head_branch: "feature", event: "pull_request", head_repository: {full_name: "o/r"}}
    @artifact = {id: 22, expired: false, size_in_bytes: zip.bytesize, workflow_run: {id: 11}}
    @pull = {state: "open", head: {sha: HEAD_SHA, ref: "feature", repo: {full_name: "o/r"}}, base: {ref: "main", repo: {default_branch: "main"}}}
  end

  def writes = requests.reject { _1.method == "GET" }

  def git_sha(text) = Digest::SHA1.hexdigest(text)

  def call(env)
    req = Rack::Request.new(env)
    return page(req) if req.path_info == "/"

    body = req.body.read
    json = body.empty? ? nil : JSON.parse(body, symbolize_names: true)
    requests << Request.new(req.request_method, req.path_info, req.query_string, env["HTTP_AUTHORIZATION"], json)
    route(req.request_method, req.path_info, json)
  end

  private

  def route(verb, path, json)
    case "#{verb} #{path}"
    when "GET /user" then reply(200, login: "reviewer")
    when %r{\AGET /repos/o/r/actions/runs/\d+\z} then runs_status ? reply(runs_status, message: "Bad credentials") : reply(200, run)
    when %r{\AGET /repos/o/r/actions/artifacts/\d+\z} then reply(200, artifact)
    when %r{\AGET /repos/o/r/actions/artifacts/\d+/zip\z} then [303, {"location" => "/blob/artifact.zip"}, []]
    when "GET /blob/artifact.zip" then [200, {"content-type" => "application/zip"}, [zip]]
    when %r{\AGET /repos/o/r/pulls/\d+\z} then reply(200, pull)
    when %r{\AGET /repos/o/r/contents/(.+)\z}
      (bytes = baselines[$1]) ? [200, {"content-type" => "application/vnd.github.raw"}, [bytes]] : reply(404, message: "Not Found")
    when "POST /repos/o/r/git/blobs" then reply(201, sha: git_sha(json[:content]))
    when %r{\AGET /repos/o/r/git/commits/\h{40}\z} then reply(200, sha: HEAD_SHA, tree: {sha: git_sha("tree of head")})
    when "POST /repos/o/r/git/trees" then reply(201, sha: git_sha(json.to_json))
    when "POST /repos/o/r/git/commits" then reply(201, sha: git_sha(json.to_json), html_url: "https://github.com/o/r/commit/#{git_sha(json.to_json)}")
    when %r{\APATCH /repos/o/r/git/refs/heads/.+\z}
      patch_status ? reply(patch_status, message: "Update is not a fast forward") : reply(200, object: {sha: json[:sha]})
    when %r{\AGET /repos/o/r/git/refs?/heads/.+\z} then reply(200, object: {sha: moved_ref_sha || HEAD_SHA})
    when %r{\APOST /repos/o/r/issues/\d+/comments\z} then reply(201, html_url: "https://github.com/o/r/pull/7#issuecomment-1")
    else reply(404, message: "fake has no route for #{verb} #{path}")
    end
  end

  def reply(status, hash) = [status, {"content-type" => "application/json"}, [JSON.generate(hash)]]

  # The page under test with its two hooks used: the API origin and the CSP.
  # Changing the script changes its hash, so the hash is recomputed here.
  def page(req)
    origin = "#{req.scheme}://#{req.host_with_port}"
    html = PAGE.read
    html = html.sub('const API = "https://api.github.com";', %(const API = "#{origin}";))
    html = html.sub("connect-src https://api.github.com", "connect-src #{origin}")
    html = html.sub(/'sha256-[^']+'/, "'#{self.class.script_sha256(html)}'")
    [200, {"content-type" => "text/html"}, [html]]
  end
end
