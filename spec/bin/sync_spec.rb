require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/sync")

RSpec.describe Sync do
  let(:workdir) { Pathname.new(Dir.mktmpdir) }
  let(:template) { workdir.join("template") }
  let(:template_origin) { workdir.join("template.git") }
  let(:fork_origin) { workdir.join("fork.git") }
  let(:clone) { workdir.join("app") }
  let(:bin) { workdir.join("bin") }
  let(:log) { workdir.join("gh.log") }
  let(:fork_changelog) { "# Changelog\n\n## [Unreleased]\n\n## v2026.10.29\n\n### Added\n\n- Our own feature.\n" }
  let(:identity) do
    { "GIT_AUTHOR_NAME" => "T", "GIT_AUTHOR_EMAIL" => "t@example.com",
      "GIT_COMMITTER_NAME" => "T", "GIT_COMMITTER_EMAIL" => "t@example.com" }
  end

  around do |example|
    saved = identity.keys.to_h { |k| [ k, ENV.fetch(k, nil) ] }
    ENV.update(identity)
    example.run
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    FileUtils.rm_rf(workdir)
  end

  def git(*args, dir: clone)
    out = IO.popen(Sync::CLEAN_GIT_ENV, [ "git", "-C", dir.to_s, *args ], err: [ :child, :out ], &:read)
    raise "git #{args.join(' ')} failed: #{out}" unless $?.success?

    out.strip
  end

  def template_release(name, file: "app.rb", content: "#{name}\n", line: "- Template change in #{name}.")
    template.join(file).write(content)
    changelog = template.join("CHANGELOG.md").read
    template.join("CHANGELOG.md").write(changelog.sub("## [Unreleased]\n", "## [Unreleased]\n\n## v#{name}\n\n### Fixed\n\n#{line}\n"))
    git("commit", "-q", "-am", "release #{name}", dir: template)
    git("tag", "v#{name}", dir: template)
    git("push", "-q", "origin", "HEAD:main", "v#{name}", dir: template)
  end

  # The fork starts from the template's first commit, with its own changelog and .fork.yml on next.
  def setup_repos
    git("init", "-q", "--bare", "-b", "main", template_origin.to_s, dir: workdir)
    git("init", "-q", "--bare", "-b", "main", fork_origin.to_s, dir: workdir)
    git("init", "-q", "-b", "main", template.to_s, dir: workdir)
    git("remote", "add", "origin", template_origin.to_s, dir: template)
    template.join("app.rb").write("base\n")
    template.join("CHANGELOG.md").write("# Changelog\n\n## [Unreleased]\n\n## v2026.10.01\n\n- Template history.\n")
    git("add", "app.rb", "CHANGELOG.md", dir: template)
    git("commit", "-q", "-m", "base", dir: template)
    git("push", "-q", "origin", "HEAD:main", dir: template)

    git("clone", "-q", template_origin.to_s, clone.to_s, dir: workdir)
    git("remote", "rename", "origin", "upstream")
    git("remote", "set-url", "upstream", "https://github.com/me/template.git")
    git("config", "url.#{template_origin}.insteadOf", "https://github.com/me/template.git")
    git("remote", "add", "origin", "git@github.com:me/app.git")
    git("config", "url.#{fork_origin}.insteadOf", "git@github.com:me/app.git")
    git("switch", "-q", "-c", "next")
    clone.join("CHANGELOG.md").write(fork_changelog)
    clone.join(".fork.yml").write({ "template_url" => "https://github.com/me/template.git" }.to_yaml)
    git("add", "CHANGELOG.md", ".fork.yml")
    git("commit", "-q", "-m", "fork")
    git("push", "-q", "origin", "next")
  end

  def install_fake_gh
    bin.mkpath
    FileUtils.touch(log)
    bin.join("gh").write(<<~SH)
      #!/bin/sh
      echo "CALL $*" >> "#{log}"
      case "$*" in "pr create"*) cat > /dev/null; echo "https://github.com/me/app/pull/7" ;; esac
    SH
    bin.join("gh").chmod(0o755)
  end

  def run_sync
    original_path = ENV["PATH"]
    original_stdout = $stdout
    install_fake_gh
    ENV["PATH"] = "#{bin}:#{original_path}"
    $stdout = StringIO.new
    described_class.new(root: clone.to_s).run
  ensure
    @output = $stdout.string if $stdout.is_a?(StringIO)
    $stdout = original_stdout
    ENV["PATH"] = original_path
  end

  def calls = log.read
  def pushed(path) = git("show", "origin/sync/template-v2026.10.31:#{path}")

  it "brings in the template's new releases, keeping the fork's changelog and linking each in a changelog.d fragment" do
    setup_repos
    template_release("2026.10.30")
    template_release("2026.10.31")

    run_sync
    git("fetch", "-q", "origin")

    expect(pushed("app.rb")).to eq("2026.10.31")
    expect(pushed("CHANGELOG.md")).to eq(fork_changelog.chomp)
    expect(pushed("changelog.d/template-v2026.10.31.md")).to eq(<<~MD.chomp)
      ### Changed

      - Brings in the template's release [v2026.10.30](https://github.com/me/template/releases/tag/v2026.10.30).
      - Brings in the template's release [v2026.10.31](https://github.com/me/template/releases/tag/v2026.10.31).
    MD
    workdir.join("fragment.md").write(pushed("changelog.d/template-v2026.10.31.md") + "\n")
    lint, linted = Open3.capture2e("bundle", "exec", "mdl", workdir.join("fragment.md").to_s, chdir: Rails.root.to_s)
    expect(linted).to be_success, lint
    expect(git("rev-list", "--parents", "-1", "origin/sync/template-v2026.10.31").split.size).to eq(3)
    expect(calls).to include("CALL pr create --base next --head sync/template-v2026.10.31")
    expect(calls).to include("CALL pr merge https://github.com/me/app/pull/7 --auto --merge")
  end

  it "lists only the releases next doesn't have yet" do
    setup_repos
    template_release("2026.10.30")
    run_sync
    git("fetch", "-q", "origin")
    git("switch", "-q", "next")
    git("merge", "-q", "--ff-only", "origin/sync/template-v2026.10.30")
    git("push", "-q", "origin", "next")
    template_release("2026.10.31")

    run_sync
    git("fetch", "-q", "origin")

    added = pushed("changelog.d/template-v2026.10.31.md").lines.grep(/^-/)
    expect(added).to contain_exactly(a_string_including("release [v2026.10.31]"))
  end

  it "says so and changes nothing when next already has the template's latest release" do
    setup_repos
    template_release("2026.10.30")
    git("fetch", "-q", "upstream")
    git("merge", "-q", "--no-edit", "-X", "ours", "upstream/main")
    git("push", "-q", "origin", "next")

    run_sync

    expect(@output).to include("next already has the template's release v2026.10.30")
    expect(git("ls-remote", "--heads", "origin")).not_to include("sync/")
    expect(calls).to be_empty
  end

  context "when the merge conflicts" do
    before do
      setup_repos
      clone.join("app.rb").write("ours\n")
      git("commit", "-q", "-am", "our app.rb")
      git("push", "-q", "origin", "next")
      template_release("2026.10.31")
    end

    it "stops with the fork's changelog already fixed, and names the files to resolve" do
      expect { run_sync }.to raise_error(Sync::Error, /app\.rb.*bin\/sync again/m)

      expect(clone.join("changelog.d/template-v2026.10.31.md").read).to include("- Brings in the template's release [v2026.10.31]")
      expect(clone.join("CHANGELOG.md").read).to eq(fork_changelog)
      expect(git("diff", "--name-only", "--diff-filter=U")).to eq("app.rb")
      expect(calls).to be_empty
    end

    it "finishes when run again once they're resolved" do
      expect { run_sync }.to raise_error(Sync::Error)
      clone.join("app.rb").write("resolved\n")
      git("add", "app.rb")

      run_sync
      git("fetch", "-q", "origin")

      expect(pushed("app.rb")).to eq("resolved")
      expect(pushed("changelog.d/template-v2026.10.31.md")).to include("- Brings in the template's release [v2026.10.31]")
      expect(calls).to include("CALL pr create --base next --head sync/template-v2026.10.31")
    end

    it "won't finish while a conflict is unresolved" do
      expect { run_sync }.to raise_error(Sync::Error)

      expect { run_sync }.to raise_error(Sync::Error, /still conflicted: app\.rb/)
      expect(calls).to be_empty
    end
  end

  it "starts over after an aborted merge, reusing the branch it left behind" do
    setup_repos
    clone.join("app.rb").write("ours\n")
    git("commit", "-q", "-am", "our app.rb")
    git("push", "-q", "origin", "next")
    template_release("2026.10.31")
    expect { run_sync }.to raise_error(Sync::Error)
    git("merge", "--abort")
    git("switch", "-q", "next")

    expect { run_sync }.to raise_error(Sync::Error, /app\.rb/)
  end

  it "stops when the sync branch is already on origin, since its PR brings that release in" do
    setup_repos
    template_release("2026.10.31")
    run_sync
    git("switch", "-q", "next")

    expect { run_sync }.to raise_error(Sync::Error, %r{sync/template-v2026\.10\.31 is already on origin})
  end

  it "refuses outside a fork" do
    setup_repos
    git("rm", "-q", ".fork.yml")
    git("commit", "-q", "-m", "not a fork")

    expect { run_sync }.to raise_error(Sync::Error, /no \.fork\.yml/)
  end

  it "refuses with uncommitted changes, which a merge could tangle" do
    setup_repos
    template_release("2026.10.30")
    clone.join("CHANGELOG.md").write("edited")

    expect { run_sync }.to raise_error(Sync::Error, /uncommitted changes/)
  end
end
