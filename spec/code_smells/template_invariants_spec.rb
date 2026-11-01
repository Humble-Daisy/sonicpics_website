require "rails_helper"
require "json"
require "yaml"

# modelrails_base is a template meant to be forked: every default it ships
# propagates into every downstream fork. This spec asserts the structural
# invariants from the 2026-05-18 8-reviewer panel review (plus additions
# since) — each catches a misconfiguration that would otherwise propagate
# silently. See /docs/developer/testing.
RSpec.describe "Template invariants" do
  # Clears the GIT_DIR family: under a hook these reads would enumerate another
  # repository's index (#789; lib/clean_git_env.rb).
  let(:clean_git_env) { CleanGitEnv::HASH }

  let(:root) { Rails.root }

  describe "Ruby version pinning is consistent across all sources of truth" do
    let(:tool_versions) { File.read(root.join(".tool-versions")) }
    let(:gemfile) { File.read(root.join("Gemfile")) }
    let(:gemfile_lock) { File.read(root.join("Gemfile.lock")) }
    let(:dockerfile) { File.read(root.join("Dockerfile")) }
    let(:deploy_yml) { File.read(root.join("config/deploy.yml")) }

    let(:tool_versions_ruby) do
      tool_versions[/^ruby\s+(\S+)/, 1]
    end

    it ".tool-versions pins a Ruby version" do
      expect(tool_versions_ruby).to be_present,
        "expected .tool-versions to declare `ruby <version>` on a line of its own"
    end

    it "Gemfile reads Ruby version from .tool-versions (Bundler is the enforcer)" do
      expect(gemfile).to match(/^ruby\s+file:\s+["']\.tool-versions["']/),
        "expected Gemfile to contain `ruby file: \".tool-versions\"` so Bundler enforces " \
        "the Ruby version everywhere bundle install runs (dev, CI, prod)"
    end

    it "Gemfile.lock captures the Ruby version in a RUBY VERSION block" do
      expect(gemfile_lock).to match(/^RUBY VERSION\n\s+ruby\s+#{Regexp.escape(tool_versions_ruby)}/),
        "expected Gemfile.lock to contain a RUBY VERSION block matching .tool-versions " \
        "(#{tool_versions_ruby}); regenerate with `bundle install`"
    end

    it "Dockerfile ARG RUBY_VERSION matches .tool-versions" do
      expect(dockerfile).to match(/^ARG RUBY_VERSION=#{Regexp.escape(tool_versions_ruby)}\b/),
        "expected Dockerfile ARG RUBY_VERSION to equal .tool-versions Ruby (#{tool_versions_ruby})"
    end

    it "hotcell/Dockerfile ARG RUBY_VERSION matches .tool-versions" do
      expect(File.read(root.join("hotcell/Dockerfile"))).to match(/^ARG RUBY_VERSION=#{Regexp.escape(tool_versions_ruby)}\b/),
        "expected the Hot Cell image's ARG RUBY_VERSION to equal .tool-versions Ruby (#{tool_versions_ruby})"
    end

    it "Dockerfile comment references .tool-versions (not the obsolete .ruby-version)" do
      expect(dockerfile).to include(".tool-versions"),
        "expected Dockerfile to reference .tool-versions in its comments"
      expect(dockerfile).not_to match(/\.ruby-version/),
        "Dockerfile still references the obsolete .ruby-version file"
    end

    it "config/deploy.yml builder.args.RUBY_VERSION matches .tool-versions" do
      deploy = YAML.safe_load(deploy_yml, aliases: true, permitted_classes: [ Symbol ])
      ruby_version_arg = deploy.dig("builder", "args", "RUBY_VERSION")

      expect(ruby_version_arg).to eq(tool_versions_ruby),
        "expected config/deploy.yml builder.args.RUBY_VERSION (#{ruby_version_arg.inspect}) " \
        "to equal .tool-versions Ruby (#{tool_versions_ruby}); uncomment and wire the args block"
    end
  end

  # The lock protects this checkout; the Gemfile requirement protects a fork.
  # A fork that resolves fresh takes the newest version the requirement admits,
  # so a floor left below a security release lets it land back on a vulnerable
  # gem with a green build. Written as requirement checks rather than equality
  # so routine bumps keep passing.
  describe "Security floors (the Gemfile must reject known-vulnerable versions)" do
    let(:gemfile) { File.read(root.join("Gemfile")) }
    let(:lockfile) { Bundler::LockfileParser.new(File.read(root.join("Gemfile.lock"))) }

    def locked_version(gem_name)
      spec = lockfile.specs.find { |s| s.name == gem_name }
      raise "#{gem_name} is not in Gemfile.lock" if spec.nil?

      spec.version
    end

    # GHSA-xr9x-r78c-5hrm / CVE-2026-66066: the last unpatched release of each series.
    let(:vulnerable_rails_releases) { %w[8.1.3 8.0.5 7.2.3.1].map { |v| Gem::Version.new(v) } }

    def rails_pin_problems(line)
      if line.match?(/\b(?:github|git):/)
        line.match?(/\bref:\s*"\h{40}"/) ? [] : [ "a git-sourced rails must pin `ref:` to a 40-character commit" ]
      else
        requirement = Gem::Requirement.new(line.scan(/"([~><=!\s\d.]+)"/).flatten)
        vulnerable_rails_releases.select { |v| requirement.satisfied_by?(v) }.map { |v| "admits #{v}" }
      end
    end

    it "reads the rails line by its shape: a released requirement or a pinned commit" do
      sha = "0" * 40
      expect(rails_pin_problems(%(gem "rails", "~> 8.2.0"))).to be_empty
      expect(rails_pin_problems(%(gem "rails", "~> 8.1.3", ">= 8.1.3.1"))).to be_empty
      expect(rails_pin_problems(%(gem "rails", "~> 8.1.3"))).to eq([ "admits 8.1.3" ])
      expect(rails_pin_problems(%(gem "rails", github: "rails/rails", ref: "#{sha}"))).to be_empty
      expect(rails_pin_problems(%(gem "rails", github: "rails/rails", branch: "main"))).not_to be_empty
      expect(rails_pin_problems(%(gem "rails", github: "rails/rails", ref: "0901f2cc"))).not_to be_empty
    end

    it "pins rails so a fresh resolve cannot land on a release vulnerable to CVE-2026-66066" do
      line = gemfile[/^gem "rails".*$/]
      expect(rails_pin_problems(line)).to be_empty, "Gemfile `#{line}`: #{rails_pin_problems(line).join("; ")}"
    end

    # The fix itself, which a git pin's version string cannot show: libvips refuses an untrusted loader.
    it "locks an Active Storage that disables libvips's untrusted loaders (the CVE-2026-66066 fix)" do
      bmp = Rails.root.join("spec/fixtures/files/unfuzzed.bmp").to_s
      expect { Vips::Image.new_from_file(bmp).avg }.to raise_error(Vips::Error)

      # The control: unblocked, this libvips reads the file, so the refusal above is the block.
      Vips.block_untrusted(false)
      expect(Vips::Image.new_from_file(bmp).avg).to be_a(Float)
    ensure
      Vips.block_untrusted(true)
    end

    # Active Storage raises at boot below this — it cannot disable the unfuzzed
    # operations through an older ruby-vips.
    it "locks ruby-vips at or above the 2.2.1 floor Active Storage requires" do
      expect(locked_version("ruby-vips")).to be >= Gem::Version.new("2.2.1")
    end
  end

  describe "Production Dockerfile hygiene" do
    let(:dockerfile) { File.read(root.join("Dockerfile")) }
    let(:dockerfile_lines) { dockerfile.lines.map(&:chomp) }

    def line_index(pattern)
      dockerfile_lines.find_index { |line| line.match?(pattern) }
    end

    it "excludes both development AND test gem groups from the production image" do
      expect(dockerfile).to match(/BUNDLE_WITHOUT="development:test"/),
        "expected BUNDLE_WITHOUT to exclude both development AND test; otherwise rspec-rails, " \
        "capybara, playwright-ruby-client etc. ship to production in every fork"
    end

    it "sets MALLOC_CONF for jemalloc tuning (tighter RSS on long-running Puma workers)" do
      expect(dockerfile).to match(/MALLOC_CONF=.*dirty_decay_ms:1000/),
        "expected Dockerfile ENV block to set MALLOC_CONF including dirty_decay_ms:1000"
      expect(dockerfile).to match(/MALLOC_CONF=.*muzzy_decay_ms:0/),
        "expected MALLOC_CONF to include muzzy_decay_ms:0"
    end

    it "copies Gemfile and runs bundle install BEFORE copying vendor/" do
      gemfile_copy = line_index(/^COPY Gemfile/)
      bundle_install = line_index(/^\s*RUN bundle install/)
      vendor_copy = line_index(/^COPY vendor\b/)

      expect(gemfile_copy).not_to be_nil, "expected a `COPY Gemfile ...` line"
      expect(bundle_install).not_to be_nil, "expected a `RUN bundle install` line"
      expect(vendor_copy).not_to be_nil, "expected a `COPY vendor/...` line"

      expect(gemfile_copy).to be < bundle_install,
        "Gemfile must be copied before bundle install runs"
      expect(bundle_install).to be < vendor_copy,
        "bundle install must run before COPY vendor/ to preserve layer cache " \
        "across vendor/ changes (e.g., markdowndocs symlink updates)"
    end

    it "COPYs .tool-versions alongside Gemfile so the `ruby file:` directive resolves at bundle install" do
      # The Gemfile uses `ruby file: ".tool-versions"` (asserted above). When
      # Bundler parses the Gemfile inside `RUN bundle install`, it must be
      # able to resolve that file — so .tool-versions has to land in /rails
      # before bundle install runs, not later via `COPY . .`.
      #
      # Caught by the manual `docker build .` smoke test post-#129. The build
      # failed with: "Could not find version file .tool-versions. Bundler
      # cannot continue."
      gemfile_copy_line_index = dockerfile_lines.find_index { |l| l.match?(/^COPY Gemfile/) }
      expect(gemfile_copy_line_index).not_to be_nil, "expected a `COPY Gemfile ...` line"

      copy_line = dockerfile_lines[gemfile_copy_line_index]
      expect(copy_line).to include(".tool-versions"),
        "Gemfile uses `ruby file: \".tool-versions\"`, so the Dockerfile must COPY " \
        ".tool-versions alongside Gemfile or `bundle install` aborts. Current COPY at " \
        "Dockerfile:#{gemfile_copy_line_index + 1}: `#{copy_line.strip}`. " \
        "Fix: `COPY Gemfile Gemfile.lock .tool-versions ./`"
    end

    it "gates bootsnap precompile parallelism on cross-arch detection (Aaron Patterson)" do
      # rails/bootsnap#495 requires -j 1 only when cross-compiling under QEMU
      # emulation (TARGETPLATFORM != BUILDPLATFORM). On native CI builds the
      # default parallel compilation is a real wall-clock win.
      expect(dockerfile).to match(/^ARG TARGETPLATFORM/),
        "expected `ARG TARGETPLATFORM` in Dockerfile so BuildKit populates the value " \
        "(required to gate bootsnap parallelism on cross-arch detection)"
      expect(dockerfile).to match(/^ARG BUILDPLATFORM/),
        "expected `ARG BUILDPLATFORM` in Dockerfile to pair with TARGETPLATFORM"

      # The conditional must reference both ARGs together (any comparison
      # form: equality on native, inequality on cross-arch).
      expect(dockerfile).to match(/TARGETPLATFORM.*BUILDPLATFORM|BUILDPLATFORM.*TARGETPLATFORM/),
        "expected Dockerfile to compare TARGETPLATFORM and BUILDPLATFORM to decide " \
        "whether bootsnap precompile uses -j 1 (cross-compile) or default parallelism (native)"
    end

    it "ships app code root-owned and chowns only the dirs Rails writes at runtime" do
      # Defense in depth (upstream Rails 8.1 pattern): a compromised runtime
      # process must not be able to rewrite app code or gems. `COPY --chown`
      # of the whole /rails tree makes every file writable by the rails user;
      # instead copy root-owned and chown only db/log/storage/tmp.
      expect(dockerfile).not_to match(/^COPY --chown=rails:rails/),
        "expected runtime COPYs to leave files root-owned (read-only to the rails user); " \
        "`COPY --chown=rails:rails` makes the entire app tree writable by the runtime user"
      expect(dockerfile).to match(/chown -R rails:rails db log storage tmp/),
        "expected `chown -R rails:rails db log storage tmp` so the only dirs Rails " \
        "writes at runtime (db:prepare, logs, Active Storage, bootsnap cache/pids) are writable"

      copy_rails = line_index(%r{^COPY --from=build /rails /rails})
      chown = line_index(/chown -R rails:rails/)
      user = line_index(/^USER 1000:1000/)

      expect(copy_rails).not_to be_nil, "expected `COPY --from=build /rails /rails` in the final stage"
      expect(chown).not_to be_nil
      expect(user).not_to be_nil

      expect(copy_rails).to be < chown,
        "the /rails COPY must land before the chown (the dirs must exist to be chowned)"
      expect(chown).to be < user,
        "USER 1000:1000 must come after the chown so the ownership change runs as root"
    end

    it "applies Debian security updates in the base stage (apt-get upgrade)" do
      # Docker Hub rebuilds ruby:slim on Debian point releases, NOT on interim
      # security updates — so a freshly pulled base can still carry packages
      # Debian already fixed (first image scan caught an OpenSSL heap UAF and
      # a poppler overflow exactly this way). `apt-get upgrade -y` in our own
      # base stage is the only reliable patch path between base rebuilds.
      expect(dockerfile).to match(/apt-get upgrade -y/),
        "expected `apt-get upgrade -y` in the base stage so Debian security fixes land " \
        "even when the ruby:slim base image lags the Debian repos"
    end
  end

  # Every assertion in the blocks below is a STATIC TEXT CHECK. They catch
  # config drift and nothing else — they cannot catch a build or provisioning
  # failure, and three of those shipped past them (#129/#132, #385/#386, #502)
  # because the only real verification was a human remembering to build locally.
  # #535 added a CI job that actually provisions the container; this asserts the
  # job still exists, so the static checks can never quietly become the only
  # line of defence again.
  describe "the devcontainer has a CI gate that actually builds it" do
    let(:workflow_path) { root.join(".github/workflows/devcontainer.yml") }

    it "ships a workflow that provisions the devcontainer" do
      expect(File.exist?(workflow_path)).to be(true),
        "expected .github/workflows/devcontainer.yml — without it the devcontainer's " \
        "only protection is the static assertions in this file, which cannot catch a " \
        "build failure (#535)"
    end

    it "runs a command INSIDE the container, not just a build" do
      workflow = YAML.safe_load(File.read(workflow_path), aliases: true)
      step = workflow.dig("jobs", "devcontainer", "steps").to_a
        .find { |s| s["uses"].to_s.start_with?("devcontainers/ci") }

      expect(step).not_to be_nil,
        "expected the devcontainers/ci action — `devcontainer build` alone never runs " \
        "postCreateCommand, and everything risky (apt installs, libvips, chromium, " \
        "bin/setup) lives in .devcontainer/setup.sh"
      expect(step.dig("with", "runCmd")).to be_present,
        "expected a runCmd: building the image proves nothing about whether the " \
        "container provisions and can drive a browser"
    end

    it "exercises the browser rather than only asserting it is installed" do
      run_cmd = YAML.safe_load(File.read(workflow_path), aliases: true)
        .dig("jobs", "devcontainer", "steps").to_a
        .filter_map { |s| s.dig("with", "runCmd") }.join("\n")

      expect(run_cmd).to match(%r{rspec .*spec/system/}m),
        "expected the gate to run a real system spec inside the container — #502 " \
        "removed the browser install and a presence check alone would still have passed"
    end
  end

  describe "Devcontainer matches production runtime (Option C: shared base image)" do
    let(:devcontainer_path) { root.join(".devcontainer/devcontainer.json") }
    let(:devcontainer) do
      raw = File.read(devcontainer_path)
      # devcontainer.json is JSONC (supports `//` line comments). Strip them
      # before handing to JSON.parse so this spec doesn't care whether the
      # file uses comments or not.
      stripped = raw.gsub(%r{^\s*//[^\n]*$}, "")
      JSON.parse(stripped)
    end
    let(:setup_sh) { File.read(root.join(".devcontainer/setup.sh")) }

    it "uses ruby:<.tool-versions>-slim as the base image to match production" do
      tool_versions_ruby = File.read(root.join(".tool-versions"))[/^ruby\s+(\S+)/, 1]

      expect(devcontainer["image"]).to eq("docker.io/library/ruby:#{tool_versions_ruby}-slim"),
        "expected devcontainer image to share the production Dockerfile's base image " \
        "(runtime parity for libvips, glibc, sqlite3, OpenSSL versions)"
    end

    it "does not include the mise feature (Ruby is now baked into the base image)" do
      mise_feature_keys = (devcontainer["features"] || {}).keys.select { |k| k.include?("mise") }

      expect(mise_feature_keys).to be_empty,
        "expected no mise-related feature in devcontainer.json; the ruby:slim base image " \
        "ships Ruby directly. Found: #{mise_feature_keys.inspect}"
    end

    it "does not install Node (Cuprite drives Chrome from Ruby; nothing in the template needs Node)" do
      node_feature_keys = (devcontainer["features"] || {}).keys.grep(/node/)

      expect(node_feature_keys).to be_empty,
        "expected no Node feature in devcontainer.json — #497 removed Node from the template " \
        "(system specs use Cuprite/ferrum, a pure-Ruby CDP driver; linters are Ruby gems). " \
        "Found: #{node_feature_keys.inspect}"
    end

    it "enables docker-outside-of-docker so `kamal deploy` works from inside the devcontainer" do
      docker_keys = (devcontainer["features"] || {}).keys.grep(/docker-outside-of-docker/)

      expect(docker_keys).not_to be_empty,
        "expected docker-outside-of-docker feature so forkers can run `kamal deploy` from " \
        "their devcontainer (otherwise: no Docker socket = opaque wall)"
    end

    it "mounts a named volume for the bundle cache (survives container rebuilds)" do
      mounts = Array(devcontainer["mounts"])

      expect(mounts).to include(match(/bundle-cache/)),
        "expected a named volume mount for /usr/local/bundle to avoid re-installing gems " \
        "on every devcontainer rebuild. Mounts: #{mounts.inspect}"
    end

    it "forwards the Rails port" do
      expect(Array(devcontainer["forwardPorts"])).to include(3000),
        "expected port 3000 forwarded for Rails"
    end

    it "labels forwarded ports via portsAttributes for visibility in VS Code's Ports panel" do
      attrs = devcontainer["portsAttributes"] || {}
      expect(attrs).to have_key("3000"),
        "expected portsAttributes.3000 entry with a label"
      expect(attrs.dig("3000", "label")).to be_present,
        "expected portsAttributes.3000.label so Rails is named in VS Code's Ports panel"
    end
  end

  describe ".devcontainer/setup.sh delegates to bin/setup (Rails convention)" do
    let(:setup_sh) { File.read(root.join(".devcontainer/setup.sh")) }

    it "invokes bin/setup rather than reimplementing its logic inline" do
      expect(setup_sh).to match(/bin\/setup/),
        "expected setup.sh to invoke `bin/setup` (Rails convention) instead of re-rolling " \
        "bundle install + db:prepare in shell"
    end

    it "no longer runs `mise install` (Ruby is in the base image now)" do
      expect(setup_sh).not_to match(/mise\s+install/),
        "setup.sh still calls `mise install`; the ruby:slim base image makes this unnecessary"
    end

    it "installs a browser for Cuprite system specs without resurrecting Node (no npm/npx)" do
      expect(setup_sh).not_to match(/\bnpm\b|\bnpx\b|node_modules/),
        "setup.sh still references npm/npx/node_modules — #497 removed Node; the devcontainer " \
        "must not resurrect it"
      expect(setup_sh).to match(/chromium|google-chrome/),
        "expected setup.sh to apt-install a browser (chromium) for Cuprite system specs — the " \
        "ruby:slim base ships none (unlike CI's ubuntu-latest runners), so without it ferrum has " \
        "no browser to drive and every system spec fails in the devcontainer"
    end

    it "installs system packages that mirror the production Dockerfile" do
      expect(setup_sh).to include("apt-get install"),
        "expected setup.sh to apt-get install dev system packages"

      required_pkgs = %w[build-essential libjemalloc2 libvips sqlite3 libyaml-dev pkg-config]
      required_pkgs.each do |pkg|
        expect(setup_sh).to include(pkg),
          "expected system package `#{pkg}` in setup.sh (mirrors production Dockerfile)"
      end
    end

    it "prints next-steps guidance pointing forkers at .env.example and bin/dev" do
      expect(setup_sh).to include("Next steps"),
        "expected setup.sh to print a 'Next steps' block after install completes"
      expect(setup_sh).to include(".env.example"),
        "expected setup.sh next-steps to reference .env.example"
      expect(setup_sh).to include("bin/dev"),
        "expected setup.sh next-steps to point at `bin/dev` as the run command"
    end
  end

  describe "Onboarding completeness (the fork-and-run experience)" do
    let(:env_example_path) { root.join(".env.example") }
    let(:application_rb) { File.read(root.join("config/application.rb")) }

    it ".env.example exists in the repo root" do
      expect(File.exist?(env_example_path)).to be(true),
        "expected .env.example at repo root so forkers know which env vars matter"
    end

    it ".env.example documents RAILS_MASTER_KEY (Rails secret loading)" do
      env_example = File.read(env_example_path)
      expect(env_example).to include("RAILS_MASTER_KEY"),
        "expected .env.example to document RAILS_MASTER_KEY"
    end

    it ".env.example documents KAMAL_REGISTRY_PASSWORD (Kamal deploy)" do
      env_example = File.read(env_example_path)
      expect(env_example).to include("KAMAL_REGISTRY_PASSWORD"),
        "expected .env.example to document KAMAL_REGISTRY_PASSWORD"
    end

    it "config/application.rb enables YJIT (Rails 8.1 free perf)" do
      expect(application_rb).to match(/config\.yjit\s*=\s*true/),
        "expected config.yjit = true in config/application.rb (Rails 8.1+ free perf on supported Ruby)"
    end

    # A fork dev copies .env.example; every ENV var the app reads that an
    # operator can meaningfully set should be there, so they aren't rediscovered
    # by grepping source (#298). Vars the harness/tooling sets — not a human
    # editing .env — are excluded here with a reason.
    excluded_env_vars = {
      "BUNDLE_GEMFILE"          => "set by Bundler, not an operator",
      "CI"                      => "set by the CI runner",
      "PIDFILE"                 => "set by bin/dev / Foreman",
      "SECRET_KEY_BASE_DUMMY"   => "set by the Dockerfile's assets:precompile RUN (build-time boot marker), never by a human editing .env",
      "SOLID_QUEUE_IN_PUMA"     => "set in config/deploy.yml env.clear, not .env (documented in deployment.md)",
      "TEST_ENV_NUMBER"         => "set by parallel_tests per worker (bin/parallel-rspec), never by a human"
    }

    it "documents every operator-settable ENV var the code reads (no rediscovery-by-grep)" do
      env_example = File.read(env_example_path)
      sources = Dir[root.join("{app,config,lib,db,bin}/**/*.{rb,yml,erb}")] + [ root.join("Rakefile").to_s ]
      read_vars = sources.flat_map do |file|
        File.read(file).scan(/ENV(?:\.fetch)?\s*[\[(]\s*["']([A-Z][A-Z0-9_]+)["']/).flatten
      end.uniq

      required = read_vars.reject { |var| excluded_env_vars.key?(var) }
      missing = required.reject { |var| env_example.include?(var) }

      expect(missing).to be_empty,
        "These ENV vars are read by the code but absent from .env.example — add them (grouped by " \
        "scope, with one-line comments), or add to excluded_env_vars with a reason: #{missing.sort.join(', ')}"
    end
  end

  describe "CI verifies the production image actually builds (closes #129/#132 gap)" do
    # Structural specs cannot detect build-time bugs like the .tool-versions
    # COPY regression from #129 (fixed in #132). The only safety net for that
    # class of bug is running `docker build .` in CI. These assertions ensure
    # that safety net stays wired up.
    let(:build_workflow_path) { root.join(".github/workflows/docker_build.yml") }
    let(:build_workflow) { YAML.safe_load(File.read(build_workflow_path), aliases: true) }
    # Psych (YAML 1.1) parses the unquoted `on:` trigger key as boolean true.
    let(:build_triggers) { build_workflow[true] }
    let(:docker_build_job) { build_workflow.dig("jobs", "docker_build") }
    let(:lefthook_config) { YAML.safe_load(File.read(root.join("lefthook.yml")), aliases: true) }
    let(:build_inputs) { %w[Dockerfile .dockerignore Gemfile Gemfile.lock .tool-versions bin/docker-entrypoint] }

    it "has a docker_build workflow with a docker_build job" do
      expect(File.exist?(build_workflow_path)).to be(true),
        "expected .github/workflows/docker_build.yml so the production Dockerfile is verified " \
        "to build. Without it, build-time regressions can ship to main (see #129 -> #132)."
      expect(docker_build_job).not_to be_nil, "expected a `docker_build` job in docker_build.yml"
    end

    it "builds on every push to main, and on a pull request only to test its own workflow" do
      expect(build_triggers.dig("pull_request", "paths")).to eq([ ".github/workflows/docker_build.yml" ]),
        "expected docker_build to run on a pull request only when its own workflow changes — a " \
        "build-input pull request is already built from scratch by image_scan, so a second build bills twice"
      expect(build_triggers.dig("push", "branches")).to include("main"),
        "expected a push trigger on main as the unfiltered backstop"
      expect(build_triggers["push"]).not_to have_key("paths"),
        "expected the push-to-main run to be unfiltered: `COPY . .` makes every file a build " \
        "input, so the merged tree is proven to build even when a PR's paths did not trigger it"
    end

    it "Lefthook's pre-push builds the image on the same inputs, diffed against main" do
      command = lefthook_config.dig("pre-push", "commands", "docker_build") || {}

      expect(command["run"].to_s).to include("bin/docker-build-check"),
        "expected the pre-push docker_build command to run bin/docker-build-check so a local " \
        "push of a build-input change proves the image builds before CI does"
      expect(command["files"].to_s).to include("origin/main"),
        "expected `files:` to diff against origin/main — a rebase replay pushes no changed files, so a " \
        "push-range filter would skip the image build on exactly the push that re-lands a build change"
      build_inputs.each do |input|
        expect(command["glob"].to_s).to include(input),
          "expected the pre-push glob to name #{input}, the same build inputs image_scan's " \
          "pull_request.paths names — the two lists must stay in sync"
      end
    end

    it "runs the image build last: every other pre-push command carries a priority, it does not" do
      commands = lefthook_config.dig("pre-push", "commands") || {}
      others = commands.except("docker_build")

      expect(others).not_to be_empty
      others.each do |name, config|
        expect(config["priority"]).to be_a(Integer).and(be > 0),
          "expected pre-push command #{name} to carry priority: N — lefthook runs piped commands " \
          "alphabetically unless told otherwise, and 0 or unset means last; the slow image build " \
          "must come after the fast gates and the suite"
      end
      expect(commands.fetch("docker_build", {})).not_to have_key("priority"),
        "expected docker_build to carry no priority (0 = run at the very end)"
    end

    it "docker_build job uses Buildx + build-push-action for native GHA layer caching" do
      next if docker_build_job.nil?

      uses_steps = Array(docker_build_job["steps"]).map { |s| s["uses"].to_s }

      expect(uses_steps).to include(match(%r{docker/setup-buildx-action})),
        "expected docker/setup-buildx-action to enable BuildKit features (cache-from/cache-to gha)"
      expect(uses_steps).to include(match(%r{docker/build-push-action})),
        "expected docker/build-push-action to run the build (with GHA cache integration)"
    end

    it "docker_build caches layers across CI runs (otherwise it's a 3-5 min wall on every PR)" do
      next if docker_build_job.nil?

      build_step = Array(docker_build_job["steps"]).find do |s|
        s["uses"].to_s.include?("docker/build-push-action")
      end
      next if build_step.nil?

      cache_from = build_step.dig("with", "cache-from").to_s
      expect(cache_from).to include("type=gha"),
        "expected cache-from: type=gha for layer reuse across CI runs " \
        "(without it, every PR pays the full 3-5 min cold build cost)"
    end
  end

  describe "CI and Lefthook run the same integrity-gated parallel suite" do
    # CI and the pre-push gate have drifted before (#371, #1424): both run bin/parallel-rspec, whose parity
    # and merged-coverage gates a raw `rspec` loses, and both audit gems against current advisories.
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }
    let(:lefthook_config) { YAML.safe_load(File.read(root.join("lefthook.yml")), aliases: true) }

    it "CI's test shards run bin/parallel-rspec" do
      run_steps = Array(ci_workflow.dig("jobs", "test_shard", "steps")).map { |s| s["run"].to_s }
      expect(run_steps).to include(match(%r{bin/parallel-rspec})),
        "expected CI's test_shard job to run bin/parallel-rspec (shard slice + parallel " \
        "suite + per-shard parity); a raw rspec invocation loses those gates"
    end

    it "takes the shard count and worker count from repository variables, defaulting to the public-runner shape" do
      split_seed_env = Array(ci_workflow.dig("jobs", "split_seed", "steps")).map { |s| s["env"].to_h.values.join(" ") }.join(" ")
      shard_job = ci_workflow.dig("jobs", "test_shard") || {}

      expect(split_seed_env).to include("vars.CI_SHARDS || 8"),
        "expected split_seed to read `vars.CI_SHARDS || 8` into a step env — a fork sets the " \
        "variable in its Actions settings instead of editing a tracked file (private forks are " \
        "billed per job; 8 shards is the free public-runner shape, not every fork's)"
      expect(shard_job.dig("strategy", "matrix", "shard").to_s).to include("fromJSON(needs.split_seed.outputs.indices)"),
        "expected the shard matrix to come from split_seed's `indices` output, not a literal list"
      expect(shard_job.dig("env", "CI_SHARD_TOTAL").to_s).to include("needs.split_seed.outputs.total"),
        "expected CI_SHARD_TOTAL to come from split_seed's `total` output so the split and the " \
        "matrix can never disagree"
      expect(shard_job.dig("env", "PARALLEL_TEST_PROCESSORS").to_s).to include("vars.CI_WORKERS || 4"),
        "expected PARALLEL_TEST_PROCESSORS to read `vars.CI_WORKERS || 4` — pinned to the public " \
        "runner's 4 vCPUs by default; a fork on a smaller runner sets its own"
    end

    it "the merged coverage floor and shard-union parity run in the test job" do
      run_steps = Array(ci_workflow.dig("jobs", "test", "steps")).map { |s| s["run"].to_s }
      expect(run_steps).to include(match(%r{bin/ci-coverage-merge})),
        "expected the test job to run bin/ci-coverage-merge — shards skip the merged " \
        "floor (each sees ~1/N of the suite), so without this job coverage is unenforced " \
        "and a shard-splitter bug that drops files is invisible"
    end

    it "the `test` job is the merge itself, and fails unless every shard succeeded (ruleset context)" do
      test_job = ci_workflow.dig("jobs", "test") || {}
      steps = Array(test_job["steps"])
      guard_index = steps.index { |s| s["run"].to_s.include?("needs.test_shard.result") }
      merge_index = steps.index { |s| s["run"].to_s.include?("bin/ci-coverage-merge") }

      expect(ci_workflow["jobs"].keys).not_to include("coverage_merge"),
        "expected one `test` job doing the merge — a separate summary job bills its own minute"
      expect(Array(test_job["needs"])).to include("test_shard")
      expect(test_job["if"].to_s).to include("always()"),
        "the ruleset requires `test` BY NAME; without `if: always()` a failed shard skips " \
        "the job, and a skipped required check reads as passing"
      expect(guard_index).not_to be_nil,
        "expected a step that fails the job unless needs.test_shard.result is success"
      expect(steps[guard_index]["run"]).to include("exit 1")
      expect(merge_index).to be > guard_index, "expected the shard guard to run before the merge"

      steps.drop(guard_index + 1).select { |s| s["if"].to_s.include?("always()") }.each do |step|
        expect(step["if"]).to include("steps.#{steps[guard_index]["id"]}.outcome"),
          "expected `#{step["name"]}` to run only after the shard guard passed — `always()` " \
          "alone would also run it on a failed shard, with nothing merged"
      end
    end

    it "Lefthook's bundler-audit refreshes the advisory database, as CI's fresh clone does" do
      run = lefthook_config.dig("pre-push", "commands", "bundler_audit", "run").to_s
      expect(run).to include("bin/bundler-audit check --update"),
        "CI clones the advisory database on every run; a local check against a stale copy passed while CI " \
        "failed on GHSA-w3mx-4vv9-hjpg (css_parser, #1424), so the pre-push gate must update it first"
    end

    it "Lefthook builds the cell image when hotcell/ changes" do
      command = lefthook_config.dig("pre-push", "commands", "hotcell_build") || {}

      expect(command["glob"].to_s).to include("hotcell/**")
      expect(command["run"].to_s).to include("docker build --pull hotcell")
      expect(command["files"].to_s).to include("origin/main...HEAD"),
        "diffed against main, like docker_build, so a rebase replay still builds the cell"
    end

    it "audits the cell's gems pre-push and in CI" do
      static_runs = Array(ci_workflow.dig("jobs", "static", "steps")).map { |step| step["run"].to_s }

      expect(lefthook_config.dig("pre-push", "commands", "bundler_audit", "run").to_s).to include("bin/bundler-audit check hotcell")
      expect(static_runs).to include(match(%r{bin/bundler-audit check hotcell})),
        "the cell's Gemfile.lock is a second dependency graph; auditing only the app's lock leaves it unchecked"
    end

    it "Lefthook's pre-push rspec command runs bin/parallel-rspec" do
      run = lefthook_config.dig("pre-push", "commands", "rspec", "run").to_s
      expect(run).to include("bin/parallel-rspec"),
        "expected the pre-push rspec gate to run bin/parallel-rspec so local pushes " \
        "get the same gates as CI (drift bit us before — see lefthook.yml's bundler_audit note)"
    end

    it "the comment-block gate runs in Lefthook pre-commit AND in CI's static job over the PR's diff" do
      hook = lefthook_config.dig("pre-commit", "commands", "comment_blocks", "run").to_s
      ci_steps = Array(ci_workflow.dig("jobs", "static", "steps")).map { |s| s["run"].to_s }

      expect(hook).to include("bin/comment-block-check"),
        "expected Lefthook pre-commit to run bin/comment-block-check on the staged files"
      expect(ci_steps).to include(match(%r{bin/comment-block-check --range})),
        "expected CI's static job to run bin/comment-block-check --range over the pull request's " \
        "diff — a skipped hook, or a fork without Lefthook, otherwise lands long comment blocks unchecked"
    end

    it "runs every static check in one job, and each check even after an earlier one fails" do
      jobs = ci_workflow.fetch("jobs")
      checks = %w[brakeman bundler-audit importmap\ audit rubocop markdown:check erb:check comment-block-check]
      steps = Array(jobs.dig("static", "steps"))

      expect(jobs.keys & %w[scan_ruby scan_js lint lint_docs]).to be_empty,
        "expected the four static jobs folded into `static` — each billed a full runner minute for seconds of work"
      checks.each do |check|
        step = steps.find { |s| s["run"].to_s.include?(check) }
        expect(step).not_to be_nil, "expected the static job to run #{check}"
        expect(step["if"].to_s).to include("!cancelled()"),
          "expected the #{check} step to run even after an earlier check fails (`if: !cancelled()`), " \
          "so one push reports every failing check, as four separate jobs did"
      end
    end
  end

  describe "a gate that ran nothing says so" do
    it "an rspec run that selects no examples fails" do
      expect(RSpec.configuration.fail_if_no_examples).to be(true),
        "expected spec_helper to set config.fail_if_no_examples — a filter that matches " \
        "nothing (a typo'd -e, a stale tag) otherwise reads as a green run of zero examples"
    end

    it "bin/comment-block-check refuses to run with no paths to check" do
      output = IO.popen(clean_git_env, [ root.join("bin/comment-block-check").to_s ], err: [ :child, :out ], &:read)

      expect([ $?.exitstatus, output ]).to match([ 64, a_string_including("nothing was checked") ])
    end
  end

  describe "CI cancels superseded runs (#486)" do
    # Without a concurrency group, a second push to a PR branch lets the stale
    # ~8-min run finish anyway — occupying runners and delaying the fresh run's
    # feedback. cancel-in-progress must be gated to pull_request events: pushes
    # to the default branch should each complete for the historical record.
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }

    it "declares a top-level concurrency block keyed on the branch/PR ref" do
      group = ci_workflow.dig("concurrency", "group").to_s
      expect(group).to include("github."),
        "expected a top-level concurrency.group keyed on the ref (e.g. github.head_ref || github.ref) " \
        "so all runs for one branch share a group and supersede each other"
    end

    it "cancels in-progress runs only for pull_request events" do
      cancel = ci_workflow.dig("concurrency", "cancel-in-progress").to_s
      expect(cancel).to include("github.event_name == 'pull_request'"),
        "expected cancel-in-progress gated to pull_request events so main-branch runs " \
        "are never cancelled mid-flight (each push to main completes for the record)"
    end
  end

  describe "every workflow job has a timeout (#1101)" do
    # Without timeout-minutes a job inherits GitHub's 360-minute default, so a
    # runner-side hang — #1101 was apt-get update stalling on one test shard —
    # blocks the required status for six hours instead of failing in minutes.
    # The slowest legitimate job here runs under four minutes.
    let(:workflows) do
      Dir.glob(root.join(".github/workflows/*.yml")).to_h do |path|
        [ File.basename(path), YAML.safe_load(File.read(path), aliases: true) ]
      end
    end

    it "declares timeout-minutes on every job in every workflow" do
      missing = workflows.flat_map do |file, workflow|
        workflow.fetch("jobs").reject { |_, job| job["timeout-minutes"].is_a?(Integer) }.keys.map { |job| "#{file}: #{job}" }
      end

      expect(missing).to be_empty,
        "expected timeout-minutes on every job (GitHub's default is 360 minutes):\n  #{missing.join("\n  ")}"
    end

    # The apt step is the one that hung: it is the only step that talks to a
    # package mirror, so it gets its own, shorter budget within the job's.
    it "gives every apt-get step its own timeout" do
      missing = workflows.flat_map do |file, workflow|
        workflow.fetch("jobs").flat_map do |name, job|
          Array(job["steps"]).select { |s| s["run"].to_s.include?("apt-get") && !s["timeout-minutes"].is_a?(Integer) }
                             .map { |s| "#{file}: #{name} / #{s['name']}" }
        end
      end

      expect(missing).to be_empty,
        "expected a step-level timeout-minutes on every apt-get step:\n  #{missing.join("\n  ")}"
    end
  end

  describe "CI scans the production image for OS-level CVEs" do
    # brakeman covers app code and bundler-audit covers gem deps, but neither
    # sees the OS packages baked into ruby:slim (glibc, openssl, sqlite3,
    # libvips). The image scan is the third layer. Policy: it runs on
    # Dockerfile-affecting PRs plus a weekly schedule — NOT on every PR —
    # because new base-image CVEs appear without any code change and would
    # red-flag unrelated green branches (same drift mode as the 2026-06-09
    # bundler-audit oauth2 CVE).
    let(:scan_workflow_path) { root.join(".github/workflows/image_scan.yml") }
    let(:scan_workflow_raw) { File.read(scan_workflow_path) }
    let(:scan_workflow) { YAML.safe_load(scan_workflow_raw, aliases: true) }
    # Psych (YAML 1.1) parses the unquoted `on:` trigger key as boolean true.
    let(:triggers) { scan_workflow[true] }
    let(:scan_job) { scan_workflow.dig("jobs", "scan_image") }
    let(:scan_steps) { Array(scan_job && scan_job["steps"]) }

    it "has an image_scan workflow with a scan_image job" do
      expect(File.exist?(scan_workflow_path)).to be(true),
        "expected .github/workflows/image_scan.yml — without it, OS-package CVEs in the " \
        "production image are invisible (brakeman/bundler-audit don't scan the image layer)"
      expect(scan_job).not_to be_nil, "expected a `scan_image` job in image_scan.yml"
    end

    it "runs weekly AND on Dockerfile-affecting PRs (not every PR)" do
      expect(triggers).to include("schedule"),
        "expected a schedule trigger so new base-image CVEs surface without waiting " \
        "for the next Dockerfile change"
      expect(triggers.dig("pull_request", "paths")).to include("Dockerfile"),
        "expected pull_request.paths to include Dockerfile so image-affecting changes " \
        "are scanned pre-merge"
    end

    it "is the one image build a build-input pull request runs" do
      inputs = %w[Dockerfile .dockerignore Gemfile Gemfile.lock .tool-versions bin/docker-entrypoint]

      expect(triggers.dig("pull_request", "paths")).to include(*inputs),
        "expected image_scan's pull_request.paths to name every build input: docker_build no longer " \
        "runs on pull requests, so this cold build is the pull request's proof that the image builds"
    end

    it "builds the same image docker_build does" do
      build_with = lambda do |workflow|
        steps = YAML.safe_load(File.read(root.join(".github/workflows/#{workflow}")), aliases: true)
          .fetch("jobs").values.flat_map { |job| job["steps"] }
        steps.find { |s| s["uses"].to_s.include?("docker/build-push-action") }["with"].slice("context", "file", "target", "platforms")
      end

      expect(build_with.call("image_scan.yml")).to eq(build_with.call("docker_build.yml")),
        "expected image_scan and docker_build to build the same image (context, Dockerfile, target, " \
        "platforms) — image_scan's build stands in for docker_build's on pull requests"
    end

    it "loads the built image so the scanner has something to scan" do
      build_step = scan_steps.find { |s| s["uses"].to_s.include?("docker/build-push-action") }
      expect(build_step).not_to be_nil, "expected a docker/build-push-action build step"

      expect(build_step.dig("with", "load")).to be(true),
        "expected load: true — without it the image exists only in the build cache " \
        "and the scanner has nothing to scan"
    end

    # This scan NEVER uses the layer cache, on any trigger (#536): GitHub
    # Actions cache scoping makes a PR replay its OWN stale apt layer, so a
    # stale-package CVE looks identical to a real one. See /docs/developer/testing.
    it "never reuses the layer cache — a cached apt layer hides current package state" do
      build_step = scan_steps.find { |s| s["uses"].to_s.include?("docker/build-push-action") }
      next if build_step.nil?

      expect(build_step.dig("with", "no-cache")).to be(true),
        "expected `no-cache: true` unconditionally. Anything conditional reintroduces " \
        "#536: a PR replays its own cached apt layer, and a stale-package failure is " \
        "indistinguishable from a real finding."
      expect(build_step.dig("with", "cache-from")).to be_nil,
        "expected no cache-from: it is dead config alongside no-cache: true, and reads " \
        "as though the scan still reuses layers"
    end

    it ".trivyignore entries each carry a rationale and a Revisit marker" do
      # The exception path only works if exceptions stay temporary and
      # explained. Every ignored CVE needs (a) a comment block above it and
      # (b) an explicit `Revisit:` line so the entry has an expiry trigger.
      trivyignore = root.join(".trivyignore")
      next unless File.exist?(trivyignore)

      blocks = File.read(trivyignore).split(/\n\s*\n/)
      cve_blocks = blocks.select { |b| b.match?(/^(CVE|GHSA)-/) }
      expect(cve_blocks).not_to be_empty, ".trivyignore exists but ignores nothing — delete it"

      cve_blocks.each do |block|
        cve = block[/^(?:CVE|GHSA)-\S+/]
        expect(block.lines.any? { |l| l.start_with?("#") }).to be(true),
          "#{cve}'s block has no comment — every ignored CVE needs a rationale"
        expect(block).to match(/Revisit:/i),
          "#{cve}'s block has no `Revisit:` line — exceptions need an expiry trigger"
      end
    end

    it "fails the run on fixable HIGH/CRITICAL CVEs (the policy gate)" do
      trivy_step = scan_steps.find { |s| s["uses"].to_s.include?("trivy-action") }
      expect(trivy_step).not_to be_nil, "expected an aquasecurity/trivy-action scan step"

      with = trivy_step["with"] || {}
      expect(with["severity"].to_s).to match(/CRITICAL/),
        "expected severity to include CRITICAL"
      expect(with["severity"].to_s).to match(/HIGH/),
        "expected severity to include HIGH"
      expect(with["exit-code"].to_s).to eq("1"),
        "expected exit-code: 1 so HIGH/CRITICAL findings fail the run (report-only scans rot)"
      expect(with["ignore-unfixed"]).to be(true),
        "expected ignore-unfixed: true — Debian-stable bases always carry unfixed CVEs; " \
        "gating on them would make the scan permanently red and ignored"
    end
  end

  describe "CI persists the spec runtime log for balanced parallel splits (#488)" do
    # tmp/parallel_runtime_rspec.log seeds time-based splitting, so CI caches it across
    # the split_seed/test_shard/test jobs (#488). See /docs/developer/testing.
    let(:ci_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/ci.yml")), aliases: true) }

    def job_steps(name) = Array(ci_workflow.dig("jobs", name, "steps"))

    it "test shards restore the runtime log; the merge job saves the reassembled one" do
      restore = job_steps("test_shard").find do |step|
        step["uses"].to_s.include?("actions/cache/restore") &&
          step.dig("with", "path").to_s.include?("parallel_runtime_rspec.log")
      end
      save = job_steps("test").find do |step|
        step["uses"].to_s.include?("actions/cache/save") &&
          step.dig("with", "path").to_s.include?("parallel_runtime_rspec.log")
      end
      expect(restore).not_to be_nil,
        "expected test_shard to restore tmp/parallel_runtime_rspec.log so in-shard " \
        "worker balancing has a seed"
      expect(save).not_to be_nil,
        "expected the test job to save the reassembled runtime log — each shard's " \
        "log holds only its own files' timings, so without the merged save the next " \
        "run's split degrades to file size (#488)"
      expect(restore.dig("with", "restore-keys").to_s).to be_present,
        "expected restore-keys on the runtime-log restore so a PR (whose exact key " \
        "misses) still restores the newest log from the base branch"
    end

    it "every shard computes its split from the frozen split_seed artifact, not the live log" do
      seed_upload = job_steps("split_seed").find { |s| s["uses"].to_s.include?("upload-artifact") }
      shard_env = ci_workflow.dig("jobs", "test_shard", "env") || {}

      expect(seed_upload).not_to be_nil, "expected split_seed to publish the frozen runtime-log snapshot"
      expect(shard_env["SHARD_RUNTIME_SOURCE"].to_s).to be_present,
        "expected test_shard to point SHARD_RUNTIME_SOURCE at the frozen seed — shards " \
        "reading the LIVE log compute different partitions (overlap + holes; caught " \
        "while building #495)"
    end
  end

  describe "Production topology safety (Rosa Gutiérrez + Ops panel, #130)" do
    # SQLite-on-Rails templates have non-obvious deploy hazards: rolling deploys
    # can race two containers on the same SQLite file; recurring jobs running in
    # Puma can be SIGKILL'd before draining; mailer jobs head-of-line-block
    # sweep jobs when they share a queue. These assertions encode the panel's
    # consensus decisions so forkers inherit safe defaults.
    let(:deploy_yml_raw) { File.read(root.join("config/deploy.yml")) }
    let(:deploy_yml) { YAML.safe_load(deploy_yml_raw, aliases: true, permitted_classes: [ Symbol ]) }
    let(:queue_yml_raw) { File.read(root.join("config/queue.yml")) }
    let(:recurring_yml_raw) { File.read(root.join("config/recurring.yml")) }

    # A structural assertion on a key name proves the key is spelled the way
    # the spec expects, not that the tool accepts it: `stop_wait_time` and a
    # `max-replicas` docker option shipped for months while `kamal config`
    # rejected the file before touching a host. Kamal's own loader is the check.
    it "config/deploy.yml is accepted by the installed Kamal's own configuration loader" do
      require "kamal"
      expect {
        Kamal::Configuration.create_from(config_file: root.join("config/deploy.yml"), version: "spec")
      }.not_to raise_error
    end

    it "servers.web is a single host with no docker options Docker rejects (SQLite is single-writer, single-host)" do
      web = deploy_yml.dig("servers", "web") || {}
      expect(Array(web["hosts"]).length).to eq(1),
        "expected exactly one web host — SQLite lives on one machine; scale out only after " \
        "graduating to a networked database. (Donal McBreen)"
      expect(web.dig("options", "max-replicas")).to be_nil,
        "`max-replicas` is not a `docker run` flag; Kamal passes servers.*.options verbatim to " \
        "`docker run`, so the deploy fails at container start"
    end

    it "deploy.yml sets stop_timeout so Solid Queue can drain gracefully on deploy" do
      expect(deploy_yml).to have_key("stop_timeout"),
        "expected `stop_timeout` at top level of deploy.yml: Docker's SIGTERM→SIGKILL grace for a " \
        "proxied role defaults to 10s, not enough for Solid Queue's on_worker_shutdown to drain " \
        "in-flight jobs. (Rosa Gutiérrez)"
      expect(deploy_yml["stop_timeout"]).to be >= 45,
        "expected stop_timeout >= 45s for SK drain (got #{deploy_yml['stop_timeout']})"
    end

    it "deploy.yml documents the SOLID_QUEUE_IN_PUMA graduation checklist for forkers" do
      # The default stays true (correct for one-box SQLite forks). The comment
      # must make the graduation path unmissable so forkers know when to flip it.
      # We just check both signals are present in the file — co-location is
      # enforced by being in the same env.clear block in practice.
      expect(deploy_yml_raw).to include("SOLID_QUEUE_IN_PUMA"),
        "expected SOLID_QUEUE_IN_PUMA referenced in deploy.yml"
      expect(deploy_yml_raw).to match(/[Gg]raduation\s+checklist|when\s+you\s+outgrow/),
        "expected deploy.yml to include an explicit graduation checklist explaining when to " \
        "flip SOLID_QUEUE_IN_PUMA and what else changes. The default propagates to every fork " \
        "— the comment is the documentation. (Donal McBreen)"
    end

    it "deploy.yml warns that the job: block requires migrating off SQLite" do
      # The currently-commented `servers.job:` block is a SQLite trap: SQLite is
      # single-host, so a separate job role can't share the DB file across
      # machines. The deploy.yml as a whole must warn forkers before they
      # uncomment that block.
      expect(deploy_yml_raw).to match(/^\s*#\s*job:/m),
        "expected a commented `# job:` block in deploy.yml"
      expect(deploy_yml_raw).to match(/SQLite.*(?:single-host|cannot.*share|trap|networked)|networked.*database.*job/im),
        "expected deploy.yml to warn that uncommenting the `job:` block requires a networked " \
        "DB (Postgres/MySQL accessory) — SQLite cannot be shared across hosts. " \
        "(Donal McBreen + Rosa Gutiérrez)"
    end

    it "queue.yml uses named queues for observability, not the queues: \"*\" wildcard" do
      queue = YAML.safe_load(queue_yml_raw, aliases: true)
      workers = queue.dig("default", "workers") || []
      expect(workers).not_to be_empty, "expected default.workers in queue.yml"

      queues_value = workers.first["queues"]
      expect(queues_value).to be_an(Array),
        "expected queues to be an explicit array (e.g., [default, mailers, low]) instead of " \
        "the \"*\" wildcard — named queues give clear operational signals when one backs up. " \
        "Got: #{queues_value.inspect}"
      expect(queues_value).to include("mailers"),
        "expected `mailers` queue declared explicitly so mailer jobs are routable separately"
    end

    it "recurring.yml routes digest_mailer to the mailers queue" do
      recurring = YAML.safe_load(recurring_yml_raw, aliases: true)
      digest_mailer = recurring.dig("production", "digest_mailer") || {}

      expect(digest_mailer["queue"]).to eq("mailers"),
        "expected digest_mailer to be routed to the `mailers` queue so it shows up in " \
        "queue-level observability (was on `default` — sharing with DB sweep jobs)"
    end

    # Solid Queue resolves a `command:` entry with no `queue:` key to
    # SolidQueue::RecurringJob, which is `queue_as :solid_queue_recurring`
    # (RecurringTask#enqueue_options compacts a nil queue away). A queue no
    # worker polls is a job that can never be claimed, and it fails silently —
    # the row is enqueued and simply sits there (#894).
    it "recurring.yml routes every entry to a queue queue.yml actually polls" do
      polled = YAML.safe_load(queue_yml_raw, aliases: true)
        .dig("default", "workers").to_a.flat_map { |worker| Array(worker["queues"]) }
      recurring = YAML.safe_load(recurring_yml_raw, aliases: true).fetch("production")

      unpolled = recurring.reject { |_name, entry| polled.include?(effective_recurring_queue(entry)) }

      expect(unpolled).to be_empty,
        "expected every config/recurring.yml entry to land on one of #{polled.inspect}; these do not: " +
        unpolled.map { |name, entry| "#{name} -> #{effective_recurring_queue(entry)}" }.join(", ")
    end

    # queue.yml declares `low: best-effort cleanup, retention sweeps`; this is
    # the assertion that the declaration is honoured. The two workspace sweeps
    # stay on `default` deliberately — they dispatch notifiers a user waits on,
    # so they must not queue behind an hour of blob purges (#894).
    # `notification_dispatch_reconcile` is on `default` for the same reason: it
    # re-delivers a notification that already failed to arrive once (#927).
    it "recurring.yml keeps cleanup sweeps on `low` and notifier sweeps on `default`" do
      recurring = YAML.safe_load(recurring_yml_raw, aliases: true).fetch("production")
      expected = {
        "clear_solid_queue_finished_jobs" => "low",
        "unattached_blobs_sweep" => "low",
        "expired_sessions_sweep" => "low",
        "webauthn_challenges_sweep" => "low",
        "activity_log_retention_sweep" => "low",
        "notification_cleanup" => "low",
        "notification_dispatch_reconcile" => "default",
        "workspace_invitation_expiring_sweep" => "default",
        "workspace_capacity_sweep" => "default"
      }

      actual = expected.keys.index_with { |name| effective_recurring_queue(recurring.fetch(name)) }

      expect(actual).to eq(expected),
        "expected config/recurring.yml to honour queue.yml's `low: best-effort cleanup, " \
        "retention sweeps` convention"
    end

    # An explicit recurring `queue:` wins over queue_as, so a disagreement is silent
    # and the class's declaration false (#1045).
    it "recurring.yml's queue agrees with the job class's own queue_as" do
      recurring = YAML.safe_load(recurring_yml_raw, aliases: true).fetch("production")
      pinned = recurring.select { |_name, entry| entry["class"].present? && entry["queue"].present? }

      # POSITIVE CONTROL: a misparse would examine nothing and pass.
      expect(pinned.size).to be >= 8,
        "only #{pinned.size} recurring entries name both a class and a queue — the parse has " \
        "stopped seeing the schedule, so a disagreement would go unreported"

      disagreeing = pinned.filter_map do |name, entry|
        declared = entry["class"].constantize.queue_name.to_s
        next if declared == entry["queue"].to_s

        "#{name}: #{entry['class']} declares `queue_as :#{declared}`, schedule says `queue: #{entry['queue']}`"
      end

      expect(disagreeing).to be_empty,
        "config/recurring.yml's `queue:` overrides the class, so these classes lie about where " \
        "they run. Change the class's queue_as to match the schedule (or drop the schedule's " \
        "`queue:` and let the class decide):\n  #{disagreeing.join("\n  ")}"
    end

    # Mirrors SolidQueue::RecurringTask: an explicit `queue:` wins, otherwise
    # the job class's own `queue_as` decides — and a `command:` entry has no
    # class, so SolidQueue::RecurringJob's does.
    def effective_recurring_queue(entry)
      return entry["queue"] if entry["queue"].present?

      job_class = entry["class"].presence&.constantize || SolidQueue::RecurringJob
      job_class.queue_name
    end

    it "database.yml declares journal_mode WAL explicitly so forks inherit the durability posture" do
      rendered = ERB.new(File.read(root.join("config/database.yml"))).result
      db = YAML.safe_load(rendered, aliases: true)

      expect(db.dig("default", "pragmas", "journal_mode")).to eq("wal"),
        "expected `pragmas: { journal_mode: wal }` in database.yml's default block. Rails 8.1 " \
        "defaults to WAL, but the template makes it explicit so a fork reads the production " \
        "durability/concurrency posture here instead of inferring it from adapter defaults " \
        "(Nate Berkopec, #304). `pragmas:` merges over Rails' DEFAULT_PRAGMAS — the other tuned " \
        "defaults (synchronous: normal, foreign_keys, mmap_size) are preserved."
      expect(db.dig("default", "timeout")).to eq(5000),
        "expected `timeout: 5000` — installs the sqlite3 busy handler so writers wait up to 5s " \
        "for the lock (NOT the busy_timeout PRAGMA; see spec/config/sqlite_pragmas_spec.rb)"
    end

    # Development wires the queue database and runs bin/jobs; without the adapter every job ran
    # in-process instead, so concurrency limits and recurring schedules behaved unlike production.
    it "runs development's jobs through Solid Queue, as production does" do
      %w[development production].each do |env|
        config = File.read(root.join("config/environments/#{env}.rb"))
        expect(config).to match(/^\s*config\.active_job\.queue_adapter = :solid_queue$/),
          "expected config/environments/#{env}.rb to set `config.active_job.queue_adapter = :solid_queue`"
      end
      expect(File.read(root.join("Procfile.dev"))).to match(/^jobs: bin\/jobs$/)
    end

    # A job in bin/jobs is a separate process; the async cable adapter reaches only its own process's browsers.
    it "carries development's broadcasts across processes, so a job's updates reach the browser" do
      cable = YAML.safe_load(File.read(root.join("config/cable.yml")), aliases: true)
      expect(cable.dig("development", "adapter")).to eq("solid_cable")
      expect(cable.dig("development", "connects_to", "database", "writing")).to eq("cable")

      db = YAML.safe_load(ERB.new(File.read(root.join("config/database.yml"))).result, aliases: true)
      expect(db.dig("development", "cable", "migrations_paths")).to eq("db/cable_migrate")
    end
  end

  describe "Devops architecture is documented for forkers (app/docs surface)" do
    # The template's devcontainer, deployment, and Solid Queue topology are
    # load-bearing decisions that propagate to every fork. Forkers need to
    # find this in app/docs/ (rendered at /docs via markdowndocs), not buried
    # in deploy.yml comments or a design spec. These assertions catch the
    # case where we change config but forget to update the doc surface.
    let(:deployment_doc_path) { root.join("app/docs/developer/deployment.md") }
    let(:background_jobs_doc_path) { root.join("app/docs/developer/background-jobs.md") }
    let(:getting_started_doc_path) { root.join("app/docs/developer/getting-started.md") }

    it "app/docs/developer/deployment.md exists and explains the Kamal+SQLite topology" do
      expect(File.exist?(deployment_doc_path)).to be(true),
        "expected app/docs/developer/deployment.md so forkers find deployment guidance via /docs/developer/deployment " \
        "(not just deploy.yml comments they only read mid-deploy)"

      content = File.read(deployment_doc_path)
      expect(content).to match(/exactly one host/i),
        "expected deployment.md to explain the single-host SQLite constraint"
      expect(content).to match(/SOLID_QUEUE_IN_PUMA/),
        "expected deployment.md to document SOLID_QUEUE_IN_PUMA topology + graduation"
      expect(content).to match(/[Gg]raduation/),
        "expected deployment.md to spell out the graduation path from SQLite/Puma defaults"
      expect(content).to match(/stop_timeout/),
        "expected deployment.md to explain stop_timeout tuning for Solid Queue drain"
    end

    it "app/docs/developer/background-jobs.md exists and documents Solid Queue topology" do
      expect(File.exist?(background_jobs_doc_path)).to be(true),
        "expected app/docs/developer/background-jobs.md so forkers find queue topology + recurring " \
        "job guidance via /docs/developer/background-jobs (not just queue.yml comments)"

      content = File.read(background_jobs_doc_path)
      expect(content).to match(/[Ss]olid [Qq]ueue/),
        "expected background-jobs.md to reference Solid Queue"
      expect(content).to match(/mailers/i),
        "expected background-jobs.md to document the `mailers` named queue"
      expect(content).to match(/default/i),
        "expected background-jobs.md to document the `default` queue convention"
    end

    it "app/docs/developer/getting-started.md mentions the docker_build CI job" do
      content = File.read(getting_started_doc_path)
      expect(content).to match(/docker_build/),
        "expected getting-started.md Gate 2 CI table to include the `docker_build` job " \
        "added in #134. Without this, forkers don't realize their PRs are CI-verified " \
        "against a real production build."
    end
  end

  describe "Repo-level documentation surfaces exist" do
    # Forkers consult CHANGELOG.md to see what's changed between fork points.
    # Asserting its existence here prevents accidental deletion during repo
    # cleanup — a class of mistake easier to make than to spot.
    it "CHANGELOG.md exists at the repo root" do
      expect(File.exist?(root.join("CHANGELOG.md"))).to be(true),
        "expected CHANGELOG.md at the repo root so forkers can see what's changed " \
        "between fork points. Use Keep a Changelog format (https://keepachangelog.com)."
    end
  end

  # bin/fork hardcodes the paths and tokens it rewrites. The fork spec runs
  # against a generated skeleton, so it stays green even if the template moves a
  # file or drops a token — and bin/fork would then silently stop renaming it.
  # A vanished token is indistinguishable from a completed rename (both mean
  # "not found"), so the script would report success while shipping template
  # branding to every fork. These pin the template side.
  # The coverage floor is enforced from two processes that never share a
  # runtime — spec/rails_helper.rb for a single-process run, bin/parallel-rspec's
  # collate for the merged parallel result. They used to be literals in both,
  # each carrying a "keep in sync" comment: an admission DRY had failed, in the
  # files whose whole job is preventing that class of drift (#496).
  describe "coverage thresholds have a single source of truth" do
    it "declares the floor and merge timeout in exactly one place" do
      sources = { "bin/parallel-rspec" => nil, "spec/rails_helper.rb" => nil }
        .keys.to_h { |f| [ f, File.read(root.join(f)) ] }

      sources.each do |file, content|
        expect(content).not_to match(/keep in sync/i),
          "#{file} still carries a 'keep in sync' comment — the thresholds belong " \
          "in spec/coverage_config.rb, which both processes read"
        expect(content).to include("CoverageConfig::"),
          "expected #{file} to read the threshold from CoverageConfig rather than " \
          "restating the literal"
      end
    end
  end

  describe "bin/fork's rename targets still exist upstream" do
    before { load Rails.root.join("bin/fork").to_s unless defined?(ForkFlow) }

    it "offers only presets the app will boot with" do
      accepted = File.read(root.join("config/initializers/tenancy.rb"))[/valid_onboarding = \[(.*?)\]/m, 1]
                     .to_s.scan(/:(\w+)/).flatten

      expect(accepted).not_to be_empty, "could not parse valid_onboarding from config/initializers/tenancy.rb"
      expect(ForkFlow::PRESETS).to match_array(accepted),
        "bin/fork offers presets #{ForkFlow::PRESETS.inspect} but config/initializers/tenancy.rb " \
        "accepts #{accepted.inspect} and raises at boot on anything else — a forker choosing an " \
        "unaccepted preset gets a .env the app refuses to start on"
    end

    # bin/setup validates the preset it reads from .fork.yml independently of
    # bin/fork, so it carries its own copy of the list and can drift.
    it "keeps bin/setup's preset validation in step with the initializer" do
      accepted = File.read(root.join("config/initializers/tenancy.rb"))[/valid_onboarding = \[(.*?)\]/m, 1]
                     .to_s.scan(/:(\w+)/).flatten
      declared = File.read(root.join("bin/setup"))[/valid_presets = %w\[(.*?)\]/m, 1].to_s.split

      expect(declared).to match_array(accepted),
        "bin/setup validates presets as #{declared.inspect} but the app accepts " \
        "#{accepted.inspect} — a drift here either rejects a valid fork or lets a " \
        "typo through into every teammate's .env"
    end

    it "names only files the template actually has" do
      missing = ForkFlow::RENAME_FILES.reject { |path| File.exist?(root.join(path)) }

      expect(missing).to be_empty,
        "bin/fork expects to rename #{missing.join(', ')}, which no longer exist — " \
        "forks would abort in preflight"
    end

    # In a fork these tokens are gone BECAUSE bin/fork ran; the check is about
    # the template's own tree, so it goes inert on the same .fork.yml signal
    # the placeholder-hygiene group below switches on. Without this every
    # fork's first CI run failed here, whatever it pushed.
    it "searches for tokens that are still present in each file" do
      skip "fork — bin/fork already consumed these tokens" if root.join(".fork.yml").exist?

      stale = ForkFlow::SUBSTITUTIONS.flat_map do |path, substitutions|
        content = File.read(root.join(path))
        substitutions.reject { |from, _| content.include?(from) }.map { |from, _| "#{path}: #{from.inspect}" }
      end

      expect(stale).to be_empty,
        "bin/fork looks for tokens that are gone: #{stale.join(', ')}. A missing token is " \
        "indistinguishable from an already-completed rename, so bin/fork would report success " \
        "while leaving template identity in every fork."
    end
  end

  describe "fork placeholder hygiene (self-activating in forks via .fork.yml)" do
    # In the template these placeholders are CORRECT — bin/fork substitutes
    # them at fork time — so the check must be inert here. .fork.yml is
    # committed provenance of a completed fork; its presence switches this on
    # with zero configuration. It closes the gap bin/fork's TODO reminder
    # leaves open: advisory output is read once, a failing spec persists until
    # someone acts (#553). merge=ours means upstream fixes to fork-owned
    # locale files never arrive on sync, so the fork's own suite is the only
    # place this class of leftover can be caught.
    it "ships no placeholder support address in fork-owned locale files" do
      skip "template repo — placeholders are correct here" unless Rails.root.join(".fork.yml").exist?

      content = Rails.root.join("config/locales/en/pages.en.yml").read
      stale = content.scan(/[\w.+-]+@[\w.-]+\.example\b/) + content.scan(/[\w.+-]+@example\.com\b/)
      expect(stale).to be_empty,
        "placeholder support address still shipping: #{stale.uniq.join(', ')} — " \
        "set a real address in config/locales/en/pages.en.yml (bin/fork listed this " \
        "in its post-fork TODOs; this spec is the durable reminder)"
    end
  end

  # bin scripts in this repo are spec'd by `load`ing them (see
  # spec/bin/parallel_rspec_spec.rb), which only works because the top-level
  # invocation is guarded. Without the guard, loading a script in a spec RUNS
  # it against the developer's own checkout — for bin/fork that means
  # `git remote rename` and a commit. Asserted on source because the safe way
  # to test "loading is safe" cannot itself be to load it.
  describe "bin scripts are safe to load in a spec" do
    %w[bin/fork bin/parallel-rspec].each do |script|
      it "#{script} guards top-level execution behind $PROGRAM_NAME" do
        source = File.read(root.join(script))

        expect(source).to match(/\$PROGRAM_NAME == __FILE__/),
          "expected #{script} to guard its top-level run with " \
          "`if $PROGRAM_NAME == __FILE__` so specs can `load` it without executing it " \
          "against the developer's checkout"
      end
    end

    # OptionParser#parse! mutates ARGV in place. Left at top level it runs on
    # load too, so `rspec --format doc` would raise InvalidOption before any
    # example ran, and parallel_tests (which reads ARGV) would see it emptied.
    it "bin/fork parses options inside the guard, not at load time" do
      source = File.read(root.join("bin/fork"))
      guard_at = source.index("$PROGRAM_NAME == __FILE__")
      parse_at = source.index("OptionParser")

      expect(guard_at).not_to be_nil, "expected bin/fork to have a $PROGRAM_NAME guard"
      expect(parse_at).to be > guard_at,
        "expected bin/fork's OptionParser block to sit INSIDE the $PROGRAM_NAME guard — " \
        "parse! mutates ARGV, so at load time it corrupts the spec runner's own arguments"
    end
  end

  describe "bin/setup leaves a checkout whose specs can pass" do
    # tailwindcss-rails enhances `assets:clobber` with `tailwindcss:clobber`,
    # so the Propshaft heal below also deletes app/assets/builds/tailwind.css.
    # bin/setup used to rebuild it only as a side effect of `exec bin/dev`,
    # which --skip-server never reaches — leaving a fork's very first
    # `bundle exec rspec` failing every system spec at once.
    let(:setup_sh) { File.read(root.join("bin/setup")) }

    # bin/fork records the tenancy preset in .fork.yml; bin/setup is what
    # applies it per clone. That split is deliberate — a teammate cloning an
    # already-forked repo runs bin/setup, never bin/fork, so if bin/setup
    # doesn't read the provenance the second developer silently runs on the
    # wrong tenancy mode.
    it "applies the fork's recorded tenancy preset to .env" do
      expect(setup_sh).to include(".fork.yml"),
        "expected bin/setup to read .fork.yml — it is the only thing a teammate runs, " \
        "so it must apply the fork's recorded preset to their .env"
      expect(setup_sh).to match(/WORKSPACE_ON_SIGNUP/),
        "expected bin/setup to write WORKSPACE_ON_SIGNUP from the recorded preset"
    end

    it "rebuilds the Tailwind stylesheet after clobbering assets" do
      clobber = setup_sh.index("assets:clobber")
      rebuild = setup_sh.index("tailwindcss:build")

      expect(clobber).not_to be_nil, "expected bin/setup to clobber precompiled assets"
      expect(rebuild).not_to be_nil,
        "expected bin/setup to run tailwindcss:build — assets:clobber removes the " \
        "compiled stylesheet, and without it every system spec fails on contrast/layout"
      expect(rebuild).to be > clobber,
        "tailwindcss:build must run AFTER assets:clobber, or the clobber deletes " \
        "the stylesheet the rebuild just produced"
    end
  end

  describe "the template ships no AI-agent configuration (forks start AI-agnostic)" do
    # Policy (2026-08-14): AI tooling is a per-developer choice layered onto a
    # fork, never inherited — the maintainer's own agent layer stays untracked
    # via .git/info/exclude. See /docs/developer/extending.
    ai_config_patterns = %r{\A(?:
      CLAUDE(?:\.local)?\.md |
      AGENTS\.md |
      GEMINI\.md |
      \.claude(?:/|-on-rails/) |
      \.cursor(?:rules|/) |
      \.aider |
      \.graphifyignore |
      agent-os/ |
      \.github/copilot-instructions\.md
    )}x

    it "tracks no AI-agent configuration files" do
      tracked = IO.popen(clean_git_env, [ "git", "-C", root.to_s, "ls-files" ], &:read)
        .to_s.lines.map(&:strip)
      offenders = tracked.grep(ai_config_patterns)

      expect(offenders).to be_empty,
        "expected no AI-agent configuration tracked in git, found: " \
        "#{offenders.join(', ')}. Forks start AI-agnostic — keep agent config " \
        "local via .git/info/exclude (never committed), or extend the pattern " \
        "here with a reason if a new tool's config genuinely must ship."
    end
  end

  describe "credentials in git: keys never, encrypted files only from a fork" do
    let(:tracked) { IO.popen(clean_git_env, [ "git", "-C", root.to_s, "ls-files", "config" ], &:read).to_s.lines.map(&:strip) }

    it "tracks no credentials key" do
      keys = tracked.grep(/master\.key\z|credentials\/.*\.key\z/)
      expect(keys).to be_empty, "expected no credentials key tracked in git, found: #{keys.join(', ')}"
    end

    it "ships no encrypted credentials from the template itself" do
      skip "fork — a fork commits the encrypted credentials its image is built from" if root.join(".fork.yml").exist?

      blobs = tracked.grep(/\.yml\.enc\z/)
      expect(blobs).to be_empty, "expected the template to track no encrypted credentials, found: #{blobs.join(', ')}"
    end
  end

  describe "a deployer's local secrets stay out of git and out of the image" do
    let(:local_secrets) { %w[config/master.key config/credentials/production.key .env fnox.local.toml age.txt] }
    let(:dockerignore_rules) do
      File.readlines(root.join(".dockerignore"), chomp: true).grep_v(/\A\s*(#|\z)/)
    end

    def git_ignores?(path)
      system(clean_git_env, "git", "-C", root.to_s, "check-ignore", "--quiet", path)
    end

    def docker_excludes?(path)
      dockerignore_rules.reduce(false) do |excluded, rule|
        pattern = rule.delete_prefix("!").delete_prefix("/")
        File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_DOTMATCH) ? !rule.start_with?("!") : excluded
      end
    end

    it "git ignores every one of them" do
      tracked_if_created = local_secrets.reject { |path| git_ignores?(path) }
      expect(tracked_if_created).to be_empty,
        "expected .gitignore to cover #{tracked_if_created.join(', ')}"
    end

    it "still lets an app commit the encrypted files it deploys from" do
      encrypted = %w[fnox.toml config/credentials/production.yml.enc config/credentials/staging.yml.enc config/credentials.yml.enc]
      ignored = encrypted.select { |path| git_ignores?(path) }
      expect(ignored).to be_empty,
        "expected #{ignored.join(', ')} to stay committable: Kamal builds the image from a clone of the commit"
    end

    it "leaves every one of them out of the Docker build context" do
      copied_into_image = local_secrets.reject { |path| docker_excludes?(path) }
      expect(copied_into_image).to be_empty,
        "expected .dockerignore to exclude #{copied_into_image.join(', ')}: `COPY . .` would bake them into the image"
    end
  end

  describe "parallel pull requests do not conflict on the changelog" do
    let(:repo) { Pathname.new(Dir.mktmpdir) }
    let(:env) do
      clean_git_env.merge("GIT_AUTHOR_NAME" => "spec", "GIT_AUTHOR_EMAIL" => "spec@example.com",
                          "GIT_COMMITTER_NAME" => "spec", "GIT_COMMITTER_EMAIL" => "spec@example.com")
    end

    after { FileUtils.rm_rf(repo) }

    def git(*args) = system(env, "git", *args, chdir: repo.to_s, out: File::NULL, err: File::NULL)

    def add_entry(line)
      changelog = repo.join("CHANGELOG.md")
      changelog.write(changelog.read.sub("### Added\n\n", "### Added\n\n#{line}\n"))
      git("commit", "-q", "-am", line)
    end

    it "keeps both sides' entries when two branches append under the same heading" do
      FileUtils.cp(root.join(".gitattributes"), repo)
      repo.join("CHANGELOG.md").write("# Changelog\n\n## [Unreleased]\n\n### Added\n\n- An earlier entry.\n")
      git("init", "-q", "-b", "main")
      git("add", ".")
      git("commit", "-q", "-m", "base")
      git("checkout", "-q", "-b", "second")
      add_entry("- The second pull request's entry.")
      git("checkout", "-q", "main")
      add_entry("- The first pull request's entry.")

      expect(git("rebase", "-q", "main", "second")).to be(true), "the rebase conflicted on CHANGELOG.md"
      expect(repo.join("CHANGELOG.md").read).to include("- The first pull request's entry.", "- The second pull request's entry.", "- An earlier entry.")
    end
  end

  describe "Fork seams (downstream disentanglement — see /docs/developer/forking)" do
    it "keeps brand identity strings in the fork-owned brand locale file" do
      brand_path = Rails.root.join("config/locales/en/brand.en.yml")
      expect(File.exist?(brand_path)).to be(true),
        "expected config/locales/en/brand.en.yml — the fork-owned home of brand strings (see /docs/developer/forking)"
      brand = YAML.load_file(brand_path)
      expect(brand.dig("en", "application", "name")).to be_present,
        "expected en.application.name in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
      expect(brand.dig("en", "application", "description")).to be_present,
        "expected en.application.description in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
      expect(brand.dig("en", "footer", "copyright")).to be_present,
        "expected en.footer.copyright in config/locales/en/brand.en.yml — brand identity strings live in the fork-owned file (see /docs/developer/forking)"
    end

    it "defines no brand strings in template-owned locale files (forks edit brand.en.yml only)" do
      app_locale = YAML.load_file(Rails.root.join("config/locales/en/application.en.yml"))
      expect(app_locale.dig("en", "application", "name")).to be_nil,
        "expected en.application.name to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
      expect(app_locale.dig("en", "application", "description")).to be_nil,
        "expected en.application.description to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
      expect(app_locale.dig("en", "footer", "copyright")).to be_nil,
        "expected en.footer.copyright to be absent from config/locales/en/application.en.yml — " \
        "brand strings must live in brand.en.yml so forks edit one file without touching template-owned locales (see /docs/developer/forking)"
    end

    it "still resolves the brand translations after the move (the views did not change)" do
      expect(I18n.exists?("application.name")).to be(true),
        "expected I18n key application.name to resolve — brand.en.yml must define en.application.name " \
        "so views using t('application.name') keep working after the brand-seam split (see /docs/developer/forking)"
      expect(I18n.exists?("application.description")).to be(true),
        "expected I18n key application.description to resolve — brand.en.yml must define en.application.description " \
        "so views using t('application.description') keep working after the brand-seam split (see /docs/developer/forking)"
      expect(I18n.exists?("footer.copyright")).to be(true),
        "expected I18n key footer.copyright to resolve — brand.en.yml must define en.footer.copyright " \
        "so views using t('footer.copyright') keep working after the brand-seam split (see /docs/developer/forking)"
    end

    it "draws product routes from the fork-owned config/routes/app.rb" do
      expect(File.read(Rails.root.join("config/routes.rb"))).to include("draw(:app)"),
        "expected config/routes.rb to call draw(:app) — product routes live in the fork-owned config/routes/app.rb (see /docs/developer/forking)"
      app_routes_path = Rails.root.join("config/routes/app.rb")
      expect(File.exist?(app_routes_path)).to be(true),
        "expected config/routes/app.rb — the fork-owned home of product routes (see /docs/developer/forking)"
      expect(File.read(app_routes_path)).to match(/^root /),
        "expected the root route in config/routes/app.rb — it moved there from config/routes.rb (see /docs/developer/forking)"
    end

    it "marks fork-owned paths merge=ours so upstream syncs keep the fork's version" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      %w[
        app/views/pages/**
        app/controllers/pages_controller.rb
        config/locales/en/pages.en.yml
        config/locales/en/brand.en.yml
        config/routes/app.rb
        .rubocop/app.yml
        config/markdowndocs_categories.local.yml
        app/assets/tailwind/tokens/_brand.css
        README.md
        app/views/shared/_site_mark.html.erb
        public/icon.svg
        public/icon.png
        public/icon-192.png
        public/icon-512.png
        public/apple-touch-icon.png
        public/favicon.ico
        config/vocabulary.local.yml
        config/initializers/project_tools.rb
      ].each do |path|
        expect(gitattributes).to match(/^#{Regexp.escape(path)} merge=ours$/),
          "expected .gitattributes to mark #{path} merge=ours"
      end
    end

    # The reverse direction, derived from the guide's own table (#1106).
    it "marks every path the fork-owned table names (the guide's promise is a contract)" do
      guide = File.read(Rails.root.join("app/docs/developer/forking.md"))
      gitattributes = File.read(Rails.root.join(".gitattributes"))

      # Bounded to the Fork-owned files section; Gemfile below merges normally.
      section = guide[/^## Fork-owned files$.*?(?=^## )/m]
      expect(section).to be_present, "the Fork-owned files section moved or was renamed"

      documented = section.lines.grep(/^\|/).drop(2).flat_map do |row|
        row.split("|")[1].to_s.scan(/`([^`]+)`/).flatten
      end
      expect(documented).to include("config/locales/en/brand.en.yml"), "table parse produced nothing recognizable"

      documented.each do |path|
        expect(gitattributes).to match(/^#{Regexp.escape(path)} merge=ours$/),
          "app/docs/developer/forking.md lists #{path} as fork-owned, but .gitattributes does not mark it " \
          "merge=ours — a fork that edits it loses its version on the next sync"
      end
    end

    it "activates the fork merge driver from bin/setup, gated on the upstream remote" do
      setup_script = File.read(Rails.root.join("bin/setup"))
      expect(setup_script).to include("merge.ours.driver"),
        "bin/setup must activate the merge=ours driver for forks"
      expect(setup_script).to include("git remote get-url upstream"),
        "driver activation must be gated on an upstream remote existing — " \
        "the template repo itself must never set the driver"
    end

    it "makes origin gh's default from bin/setup, since gh would pick the upstream remote it adds" do
      expect(File.read(Rails.root.join("bin/setup"))).to include("git config remote.origin.gh-resolved base"),
        "a teammate's gh commands in a fork clone would act on the template"
    end

    it "marks the fork extension point in db/seeds.rb" do
      expect(File.read(Rails.root.join("db/seeds.rb")))
        .to include("Fork seam: add your app's domain seeds BELOW this line"),
        "db/seeds.rb needs the end-of-template marker so forks add seeds below it (see /docs/developer/forking)"
    end

    it "documents every merge=ours path in the forking guide (no silent contract drift)" do
      gitattributes = File.read(Rails.root.join(".gitattributes"))
      guide = File.read(Rails.root.join("app/docs/developer/forking.md"))
      gitattributes.scan(/^(\S+) merge=ours$/).flatten.each do |path|
        expect(guide).to include(path),
          "#{path} is marked merge=ours in .gitattributes but not mentioned in app/docs/developer/forking.md"
      end
    end

    it "hardcodes the brand name in no template-owned locale file (sweep beyond application.en.yml)" do
      brand_name = YAML.load_file(Rails.root.join("config/locales/en/brand.en.yml"))
        .dig("en", "application", "name")
      fork_owned = %w[config/locales/en/brand.en.yml config/locales/en/pages.en.yml]
        .map { |path| Rails.root.join(path).to_s }
      Dir[Rails.root.join("config/locales/**/*.yml")].sort.reject { |file| fork_owned.include?(file) }.each do |file|
        expect(File.read(file)).not_to include(brand_name),
          "#{file.delete_prefix("#{Rails.root}/")} hardcodes the brand name #{brand_name.inspect} — " \
          "brand strings live only in fork-owned brand.en.yml (see /docs/developer/forking)"
      end
    end

    it "lets forks override brand colors in a fork-owned file imported after the template defaults" do
      brand_css = Rails.root.join("app/assets/tailwind/tokens/_brand.css")
      expect(File.exist?(brand_css)).to be(true),
        "expected app/assets/tailwind/tokens/_brand.css — the fork-owned brand-color override file (see /docs/developer/forking)"

      app_css = File.read(Rails.root.join("app/assets/tailwind/application.css"))
      primitives_at = app_css.index("./tokens/_primitives.css")
      brand_at = app_css.index("./tokens/_brand.css")
      expect(brand_at).not_to be_nil,
        "application.css must @import ./tokens/_brand.css so a fork's color overrides take effect"
      expect(brand_at).to be > primitives_at,
        "_brand.css must be imported AFTER _primitives.css so a fork's overrides win the cascade"
    end
  end

  describe "CI lint tooling is version-pinned (no silent drift across CI, local, and forks)" do
    # Was npm-based (package.json + package-lock.json), replaced with Ruby
    # gems (erb_lint, mdl) — Bundler/Gemfile.lock pin exact versions the same
    # way, and `bundle exec` doesn't have npm's "unpinned global install"
    # footgun (see #299) at all, so there's no equivalent failure mode to
    # guard against there.
    let(:gemfile_lock) { File.read(root.join("Gemfile.lock")) }

    it "pins the lint gems in Gemfile.lock at an exact resolved version" do
      %w[erb_lint mdl].each do |gem_name|
        expect(gemfile_lock).to match(/^\s+#{Regexp.escape(gem_name)}\s+\(\d+\.\d+\.\d+\)/),
          "expected #{gem_name} pinned to an exact resolved version in Gemfile.lock, " \
          "so CI, local, and forks run the same linter"
      end
    end

    it "invokes the linters via bundle exec, not a bare global command" do
      expect(File.read(root.join("lib/tasks/markdown_lint.rake"))).to include("bundle exec mdl"),
        "markdown:check must run the pinned local mdl via bundle exec, not a bare global `mdl`"
      expect(File.read(root.join("lib/tasks/erb_lint.rake"))).to include("bundle exec erb_lint"),
        "erb:check must run the pinned local erb_lint via bundle exec, not a bare global `erb_lint`"
    end

    it "ships no leftover Node toolchain (package.json, lockfile, or .tool-versions entry)" do
      %w[package.json package-lock.json].each do |file|
        expect(File.exist?(root.join(file))).to be(false),
          "expected #{file} to be absent — lint tooling is Ruby-gem-based now, a leftover Node " \
          "manifest would re-invite the drift/toolchain-duplication this describe block guards against"
      end
      tool_versions = File.read(root.join(".tool-versions"))
      expect(tool_versions).not_to match(/^node\b/),
        "expected no `node` line in .tool-versions — nothing in the template needs Node anymore"
    end

    it "does not force brakeman to the latest released version (same drift anti-pattern)" do
      # Active code only — an explanatory comment naming the removed flag is fine.
      active = File.read(root.join("bin/brakeman")).lines.reject { |line| line.strip.start_with?("#") }.join
      expect(active).not_to include("--ensure-latest"),
        "bin/brakeman --ensure-latest fails CI the moment a newer brakeman ships, on every branch with no code change — " \
        "bump deliberately instead (see #299; the drift it caused is PR #319)"
    end
  end

  describe "GitHub Actions are SHA-pinned (supply-chain integrity)" do
    # A version tag (`@v7`) is a moving pointer a compromised upstream can
    # re-aim at malicious code; a 40-hex commit SHA is content-addressed.
    # The trailing `# <tag>` comment is what Dependabot's updater rewrites on
    # grouped weekly bumps — it is load-bearing, not decoration. Covers
    # composite actions too (.github/actions/**) so they can't launder an
    # unpinned `uses:` — forward-looking; the directory doesn't exist today.
    let(:pinnable_uses_refs) do
      globs = %w[
        .github/workflows/*.yml .github/workflows/*.yaml
        .github/actions/**/action.yml .github/actions/**/action.yaml
      ]
      globs.flat_map { |glob| Dir[root.join(glob).to_s] }.flat_map do |path|
        File.foreach(path).with_index(1).filter_map do |line, lineno|
          match = line.match(/^\s*(?:-\s+)?uses:\s*["']?(?<ref>[^\s"'#]+)/)
          next unless match
          ref = match[:ref]
          next if ref.start_with?("./")        # in-repo refs move with the repo — no external exposure
          next if ref.start_with?("docker://") # image digests are a different pinning mechanism
          [ "#{Pathname(path).relative_path_from(root)}:#{lineno}", ref ]
        end
      end
    end

    it "pins every external uses: ref to a 40-hex commit SHA" do
      # The anchor sits on the ref tail, so the reusable-workflow form
      # (owner/repo/.github/workflows/x.yml@sha) is covered identically.
      offenders = pinnable_uses_refs.reject { |(_site, ref)| ref.match?(/@[0-9a-f]{40}\z/) }
      expect(offenders).to be_empty,
        "expected every external `uses:` pinned as owner/repo@<40-hex-sha> # <tag>, got:\n" +
        offenders.map { |site, ref| "  #{site} #{ref}" }.join("\n")
    end
  end

  describe "no workflow runs on pull_request_target" do
    let(:triggers_by_workflow) do
      Dir[root.join(".github/workflows/*.{yml,yaml}").to_s].to_h do |path|
        on = YAML.safe_load(File.read(path), aliases: true).then { |workflow| workflow[true] || workflow["on"] }
        [ Pathname(path).relative_path_from(root).to_s, Array(on.is_a?(Hash) ? on.keys : on) ]
      end
    end

    it "reads a trigger from every workflow" do
      expect(triggers_by_workflow.reject { |_path, triggers| triggers.any? }.keys).to be_empty
    end

    it "keeps every workflow off the trigger that pairs a writable token with a pull request's code" do
      offenders = triggers_by_workflow.select { |_path, triggers| triggers.include?("pull_request_target") }.keys
      expect(offenders).to be_empty,
        "expected no workflow on pull_request_target, found: #{offenders.join(', ')}"
    end
  end

  describe "jactionlint audits the workflows at one version, in CI and before a push" do
    let(:audit_steps) do
      YAML.safe_load(File.read(root.join(".github/workflows/workflow_audit.yml")), aliases: true)
        .fetch("jobs").values.flat_map { |job| job["steps"] }
    end
    let(:mise_tools) { File.read(root.join("mise.toml")).scan(/^([\w-]+) = "([^"]+)"$/).to_h }

    it "pins jactionlint and the shellcheck it runs to exact versions that mise.lock locks" do
      expect(mise_tools.keys).to include("jactionlint", "shellcheck")
      mise_lock = File.read(root.join("mise.lock"))
      mise_tools.each do |tool, version|
        expect(version).to match(/\A\d+\.\d+\.\d+\z/), "expected mise.toml to pin #{tool} to an exact X.Y.Z"
        expect(mise_lock).to include(%([[tools.#{tool}]]\nversion = "#{version}")),
          "expected mise.lock to lock #{tool} #{version}; run `mise lock #{mise_tools.keys.join(' ')}`"
      end
    end

    it "installs exactly mise.toml's tools in CI, from the lockfile, and runs the online checks" do
      install = audit_steps.find { |step| step["uses"].to_s.start_with?("jdx/mise-action@") }
      lint = audit_steps.find { |step| step["run"].to_s.include?("jactionlint") }

      expect(install&.dig("with", "install_args").to_s.split).to match_array(mise_tools.keys),
        "expected jdx/mise-action to install mise.toml's tools alone, not compile the .tool-versions Ruby"
      expect(lint&.dig("run")).to include("--online")
      expect(lint&.dig("env", "GITHUB_TOKEN")).to eq("${{ github.token }}")
    end

    it "runs the same jactionlint before a push that changes .github" do
      command = YAML.safe_load(File.read(root.join("lefthook.yml")), aliases: true).dig("pre-push", "commands", "jactionlint") || {}
      expect(command["run"].to_s).to start_with("mise exec -- jactionlint")
      expect(command["glob"].to_s).to include(".github/**")
    end
  end

  describe "Dependabot leaves the git-tag-pinned design-system gem to hand bumps (#1261)" do
    # To Dependabot a git gem's current version is the lockfile SHA, so its default
    # cooldown proposes the newest OLDER tag as a bump — see /docs/developer/forking.
    let(:bundler_updates) do
      config = YAML.safe_load(File.read(root.join(".github/dependabot.yml")))
      config.fetch("updates").find { |update| update["package-ecosystem"] == "bundler" }
    end

    it "ignores modelrails_ui in the bundler block" do
      expect(bundler_updates).not_to be_nil, "expected a bundler block in .github/dependabot.yml"

      ignored = Array(bundler_updates["ignore"]).map { |entry| entry["dependency-name"] }
      expect(ignored).to include("modelrails_ui"),
        "expected .github/dependabot.yml to ignore modelrails_ui in its bundler block — " \
        "a git-tag gem is bumped by hand (re-vendor pre-flight, generator, parity), and " \
        "Dependabot's cooldown has proposed it as a downgrade three times (#665, #888, #1261)"
    end

    it "groups bundler updates into one weekly pull request, as the actions already are" do
      groups = Array(bundler_updates && bundler_updates["groups"]&.values)
      patterns = groups.flat_map { |group| Array(group["patterns"]) }

      expect(patterns).to include("*"),
        "expected the bundler block to carry a group matching \"*\" — one PR per week instead " \
        "of one per gem. Each ungrouped bump fires CI, Image Scan and Devcontainer on every fork; " \
        "on a private fork that was ~87 billed minutes per gem, six gems in one morning (2026-10-14)"
    end

    it "ignores exactly the git-pinned gems and the Hot Cell family" do
      lockfile = Bundler::LockfileParser.new(File.read(root.join("Gemfile.lock")))
      from_git = lockfile.specs.select { |s| s.source.is_a?(Bundler::Source::Git) }.map(&:name)
      hotcell = lockfile.specs.map(&:name).grep(/\A(hotcell|activestorage-hotcell)/)
      hand_bumped = (from_git + hotcell).uniq.sort
      ignored = Array(bundler_updates["ignore"]).map { |entry| entry["dependency-name"] }.sort

      expect(ignored).to eq(hand_bumped),
        "Dependabot's bundler ignore must list exactly the git-pinned gems and the Hot Cell family (bumped by hand " \
        "in both lockfiles together). Missing: #{(hand_bumped - ignored).join(", ")}; no longer hand-bumped, so drop " \
        "the ignore: #{(ignored - hand_bumped).join(", ")} (/docs/developer/getting-started, /docs/developer/hot-cell)"
    end
  end

  describe "Hot Cell ships wired but off" do
    it "names no Hot Cell class in any environment file" do
      hits = Dir[root.join("config/environments/*.rb")].select { |file| File.read(file).match?(/HotCell/) }

      expect(hits).to be_empty,
        "the Hot Cell flip lives only in config/initializers/hotcell.rb, keyed on the cell being enabled: #{hits.join(", ")}"
      expect(File.read(root.join("config/initializers/hotcell.rb"))).to include('HotCell.register "active_storage"')
    end

    it "loads the client everywhere and the server only in test" do
      gemfile = File.read(root.join("Gemfile"))

      expect(gemfile).to match(/^gem "activestorage-hotcell-client"/)
      expect(gemfile[/^group :test do(.*?)^end/m, 1]).to include('gem "activestorage-hotcell-server", require: false'),
        "the cell's gems belong in the test group only, for the proving spec; the production image installs without it"
    end

    hotcell_versions = lambda do |*lockfiles|
      lockfiles.flat_map do |lockfile|
        Bundler::LockfileParser.new(lockfile).specs.select { |spec| spec.name.match?(/\A(hotcell|activestorage-hotcell)/) }
      end.map { |spec| "#{spec.name} #{spec.version}" }.uniq
    end

    it "Dependabot leaves the Hot Cell gems to a hand bump of both lockfiles" do
      updates = YAML.safe_load(File.read(root.join(".github/dependabot.yml"))).fetch("updates")
      bundler = updates.find { |update| update["package-ecosystem"] == "bundler" }
      family = hotcell_versions.call(File.read(root.join("Gemfile.lock"))).map { |entry| entry.split.first }

      expect(family).to include("activestorage-hotcell-client", "hotcell-client")
      expect(Array(bundler["ignore"]).map { |entry| entry["dependency-name"] }).to include(*family),
        "a Dependabot bump of one lockfile alone would leave the app and the cell on different Hot Cell versions"
      expect(updates.flat_map { |update| Array(update["directories"] || update["directory"]) }).not_to include("/hotcell")
    end

    it "the app and the cell lock the same Hot Cell version" do
      app_lock = File.read(root.join("Gemfile.lock"))
      locked = hotcell_versions.call(app_lock, File.read(root.join("hotcell/Gemfile.lock")))

      expect(locked.map { |entry| entry.split.last }.uniq.size).to eq(1),
        "the app's client and the cell's server must run one Hot Cell version: #{locked.sort.join(", ")}"
      expect(locked.map(&:split).map(&:first)).to include("hotcell-client", "hotcell-server", "activestorage-hotcell-server")
    end

    it "catches a cell locked to another Hot Cell version" do
      skewed = File.read(root.join("hotcell/Gemfile.lock")).sub(/^    hotcell-server \([^)]+\)/, "    hotcell-server (9.9.9)")
      expect(skewed).to include("hotcell-server (9.9.9)"), "the injection point moved; the simulation proves nothing"

      versions = hotcell_versions.call(File.read(root.join("Gemfile.lock")), skewed).map { |entry| entry.split.last }.uniq
      expect(versions.size).to eq(2)
    end

    configured_operations = lambda do |initializer|
      prefix = "ActiveStorage::HotCell::Client::"
      stack = [ Prism.parse(initializer).value ]
      found = []
      while (node = stack.pop)
        if node.is_a?(Prism::ConstantPathNode) && node.full_name.start_with?(prefix)
          found << "active_storage/hot_cell/server/#{node.full_name.delete_prefix(prefix).split("::").map(&:underscore).join("/")}"
        else
          stack.concat(node.compact_child_nodes)
        end
      end
      found.uniq
    end

    required_operations = lambda do |operation_sources|
      operation_sources.flat_map do |source|
        stack = [ Prism.parse(source).value ]
        found = []
        while (node = stack.pop)
          argument = node.is_a?(Prism::CallNode) && node.name == :require ? node.arguments&.arguments&.first : nil
          found << argument.unescaped if argument.is_a?(Prism::StringNode)
          stack.concat(node.compact_child_nodes)
        end
        found
      end
    end

    let(:initializer) { File.read(root.join("config/initializers/hotcell.rb")) }
    let(:operation_sources) { Dir[root.join("hotcell/operations/**/*.rb")].map { |file| File.read(file) } }

    it "the cell serves exactly the operations the app configures" do
      expect(configured_operations.call(initializer)).to include("active_storage/hot_cell/server/transformers/image/vips")
      expect(required_operations.call(operation_sources)).to match_array(configured_operations.call(initializer)),
        "every Hot Cell class config/initializers/hotcell.rb names needs its operation required under hotcell/operations/, " \
        "and the cell requires nothing the app never calls (/docs/developer/hot-cell)"
    end

    it "the Hot Cell docs sample keeps every volume deploy.yml already mounts" do
      skip "fork — bin/fork renames deploy.yml's volumes and leaves the template's docs as they are" if root.join(".fork.yml").exist?
      doc = File.read(root.join("app/docs/developer/hot-cell.md"))
      sample = doc.scan(/^ *```yaml\n(.*?)^ *```/m).flatten.find { |block| block.include?("accessories:") }
      existing = YAML.safe_load(File.read(root.join("config/deploy.yml")), aliases: true, permitted_classes: [ Symbol ])["volumes"]

      expect(sample).to be_present
      expect(YAML.safe_load(sample.gsub(/^ {3}/, ""), aliases: true)["volumes"]).to include(*existing),
        "a YAML key listed twice keeps only the last value, so a copied sample without #{existing.inspect} drops " \
        "the app's SQLite and Active Storage volume"
    end

    it "the Hot Cell docs sample's gid is the cell image's user" do
      gid = File.read(root.join("hotcell/Dockerfile"))[/groupadd --gid (\d+)/, 1]
      doc = File.read(root.join("app/docs/developer/hot-cell.md"))

      expect(gid).to be_present
      expect(doc).to include(%(HOTCELL_GROUP: "#{gid}"), "group-add: #{gid}", %(user: "#{gid}:#{gid}")),
        "the app's group-add, HOTCELL_GROUP and the accessory's user must all be the cell image's gid (#{gid}), " \
        "or every conversion fails with EPERM after deploy"
    end

    it "the cell answers before the app stops waiting" do
      keywords = lambda do |source, method|
        stack = [ Prism.parse(source).value ]
        found = {}
        while (node = stack.pop)
          if node.is_a?(Prism::CallNode) && node.name == method
            node.arguments&.arguments&.grep(Prism::KeywordHashNode)&.each do |hash|
              hash.elements.each { |pair| found[pair.key.unescaped.to_sym] = pair.value.slice if pair.key.is_a?(Prism::SymbolNode) }
            end
          end
          stack.concat(node.compact_child_nodes)
        end
        found
      end
      limits = keywords.call(File.read(root.join("hotcell/config.rb")), :limits)
      timeout = Integer(keywords.call(initializer, :register).fetch(:timeout, "30"))
      answer_within = Integer(limits.fetch(:queue_wait, "10")) + Integer(limits.fetch(:deadline, "60")) + 1

      expect(answer_within).to be < timeout,
        "the cell may take #{answer_within}s (queue_wait + deadline + 1) and the app waits #{timeout}s: every boot warns, " \
        "and a slow request is a client timeout instead of the cell's own answer (/docs/developer/hot-cell, Tune it)"
    end

    it "catches an operation the app never calls, and a class the cell does not serve" do
      extra = operation_sources + [ %(require "active_storage/hot_cell/server/previewers/pdf/mutool"\n) ]
      expect(required_operations.call(extra)).not_to match_array(configured_operations.call(initializer))

      unserved = initializer.sub("previewers = []", "previewers = [ ActiveStorage::HotCell::Client::Previewers::Pdf::Mutool ]")
      expect(unserved).not_to eq(initializer), "the injection point moved; the simulation proves nothing"
      expect(required_operations.call(operation_sources)).not_to match_array(configured_operations.call(unserved))
    end
  end

  describe "CI scans the cell image" do
    let(:scan_workflow) { YAML.safe_load(File.read(root.join(".github/workflows/hotcell_image_scan.yml")), aliases: true) }
    let(:triggers) { scan_workflow[true] }
    let(:scan_job) { scan_workflow.dig("jobs", "scan_hotcell_image") || {} }
    let(:build_step) { Array(scan_job["steps"]).find { |step| step["uses"].to_s.include?("docker/build-push-action") } || {} }
    let(:trivy_step) { Array(scan_job["steps"]).find { |step| step["uses"].to_s.include?("aquasecurity/trivy-action") } || {} }

    it "runs on changes to the cell, and weekly only where a fork asks" do
      expect(triggers.dig("pull_request", "paths")).to include("hotcell/**", ".github/workflows/hotcell_image_scan.yml")
      expect(triggers).to include("schedule")
      expect(scan_job["if"].to_s).to include("vars.HOTCELL_SCAN"),
        "a fork that keeps the cell off must not pay for a weekly cold build of it"
    end

    it "builds the cell from scratch and loads it for the scanner" do
      expect(build_step.dig("with", "context")).to eq("hotcell")
      expect(build_step.dig("with", "load")).to be(true)
      expect(build_step.dig("with", "no-cache")).to be(true), "a cached apt layer hides current package state (#536)"
      expect(build_step.dig("with", "cache-from")).to be_nil
    end

    it "fails on a fixable HIGH or CRITICAL finding" do
      expect(trivy_step.dig("with", "severity")).to eq("CRITICAL,HIGH")
      expect(trivy_step.dig("with", "exit-code")).to eq("1")
      expect(trivy_step.dig("with", "image-ref")).to eq(build_step.dig("with", "tags"))
    end
  end

  describe "Hot Cell ships wired but off" do
    it "names no Hot Cell class in any environment file" do
      hits = Dir[root.join("config/environments/*.rb")].select { |file| File.read(file).match?(/HotCell/) }

      expect(hits).to be_empty,
        "the Hot Cell flip lives only in config/initializers/hotcell.rb, keyed on the cell being enabled: #{hits.join(", ")}"
      expect(File.read(root.join("config/initializers/hotcell.rb"))).to include('HotCell.register "active_storage"')
    end

    it "loads the client everywhere and the server only in test" do
      gemfile = File.read(root.join("Gemfile"))

      expect(gemfile).to match(/^gem "activestorage-hotcell-client"/)
      expect(gemfile[/^group :test do(.*?)^end/m, 1]).to include('gem "activestorage-hotcell-server", require: false'),
        "the cell's gems belong in the test group only, for the proving spec; the production image installs without it"
    end
  end
end
