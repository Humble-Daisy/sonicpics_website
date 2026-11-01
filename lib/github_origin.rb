# frozen_string_literal: true

require "open3"
require_relative "clean_git_env"

# The GitHub repository a checkout's origin names. gh prefers a remote called upstream,
# which bin/fork points at the template, so scripts ask for origin by name instead.
module GithubOrigin
  URL = %r{github\.com[:/](?<repo>[^/\s]+/[^/\s]+?)(?:\.git)?/?\z}

  module_function

  def repo(root)
    url, status = Open3.capture2(CleanGitEnv::HASH, "git", "-C", root, "config", "--get", "remote.origin.url", err: File::NULL)
    url.strip[URL, :repo] if status.success?
  end
end
