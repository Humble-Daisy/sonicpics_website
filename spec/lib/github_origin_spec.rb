require "rails_helper"
require "tmpdir"

RSpec.describe GithubOrigin do
  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      system(CleanGitEnv::HASH, "git", "-C", dir, "init", "-q", exception: true)
      example.run
    end
  end

  def origin(url) = system(CleanGitEnv::HASH, "git", "-C", @dir, "remote", "add", "origin", url, exception: true)

  {
    "git@github.com:me/app.git" => "me/app",
    "git@github.com:me/app" => "me/app",
    "https://github.com/me/app.git" => "me/app",
    "https://github.com/me/my.app" => "me/my.app",
    "ssh://git@github.com/me/app.git" => "me/app"
  }.each do |url, repo|
    it "reads #{repo} from an origin of #{url}" do
      origin(url)

      expect(described_class.repo(@dir)).to eq(repo)
    end
  end

  it "reads nothing from an origin outside GitHub" do
    origin("/srv/git/app.git")

    expect(described_class.repo(@dir)).to be_nil
  end

  it "reads nothing without an origin, whatever upstream says" do
    system(CleanGitEnv::HASH, "git", "-C", @dir, "remote", "add", "upstream", "git@github.com:me/template.git", exception: true)

    expect(described_class.repo(@dir)).to be_nil
  end
end
