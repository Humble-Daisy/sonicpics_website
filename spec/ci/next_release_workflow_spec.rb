require "rails_helper"
require "yaml"

RSpec.describe "the next-release workflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/next_release.yml"), aliases: true) }
  let(:triggers) { workflow[true] || workflow["on"] }
  let(:prepare) { workflow.dig("jobs", "prepare") }
  let(:cut) { workflow.dig("jobs", "cut") }
  let(:release_step) { ->(job) { job["steps"].find { |step| step["run"].to_s.include?("bin/release") } } }

  it "runs when a pull request into next closes, and when CI finishes on next" do
    expect(triggers.keys).to contain_exactly("pull_request", "workflow_run")
    expect(triggers["pull_request"]).to eq("types" => [ "closed" ], "branches" => [ "next" ])
    expect(triggers["workflow_run"]).to eq("workflows" => [ "CI" ], "types" => [ "completed" ], "branches" => [ "next" ])
  end

  it "installs the bundle before bin/release, which runs from the release_flow gem" do
    [ prepare, cut ].each do |job|
      ruby = job["steps"].find { |step| step["uses"].to_s.start_with?("ruby/setup-ruby@") }
      expect(ruby.dig("with", "bundler-cache")).to be(true)
    end
  end

  it "stays off until the AUTO_RELEASE repository variable says true" do
    expect([ prepare["if"], cut["if"] ]).to all(include("vars.AUTO_RELEASE == 'true'"))
  end

  it "names the next release after any merge into next from this repository's own branches" do
    expect(prepare["if"]).to include("github.event_name == 'pull_request'")
      .and include("github.event.pull_request.merged")
      .and include("github.event.pull_request.head.repo.full_name == github.repository")
    expect(prepare["if"]).not_to include("head.ref")
    expect(release_step.(prepare)["run"]).to include("bin/release prepare --if-needed")
  end

  it "tries the cut whenever CI passes or fails on a push to next, so a failure stops it loudly instead of skipping it" do
    expect(cut["if"]).to include("github.event_name == 'workflow_run'")
      .and include("github.event.workflow_run.event == 'push'")
      .and include("(github.event.workflow_run.conclusion == 'success' || github.event.workflow_run.conclusion == 'failure')")
    expect(release_step.(cut)["run"]).to include("bin/release cut --if-needed")
  end

  it "pushes and opens PRs with RELEASE_TOKEN, since GitHub runs no checks on PRs the built-in token opens" do
    expect([ prepare, cut ].map { |job| release_step.(job).dig("env", "GH_TOKEN") }).to all(eq("${{ secrets.RELEASE_TOKEN }}"))
  end

  it "stops each job first, saying so plainly, when the RELEASE_TOKEN secret isn't set" do
    [ prepare, cut ].each do |job|
      check = job["steps"].first
      expect(check["env"]).to eq("RELEASE_TOKEN" => "${{ secrets.RELEASE_TOKEN }}")

      said, missing = Open3.capture2e({ "RELEASE_TOKEN" => "" }, "bash", "-e", "-c", check["run"])
      expect(missing).not_to be_success
      expect(said).to include("RELEASE_TOKEN isn't set").and include("/docs/developer/releasing")

      _, present = Open3.capture2e({ "RELEASE_TOKEN" => "a-token" }, "bash", "-e", "-c", check["run"])
      expect(present).to be_success
    end
  end

  it "queues each job behind its own earlier run, so a cut never waits behind a prepare or is cancelled by one" do
    expect([ prepare, cut ].map { |job| job.dig("concurrency", "group") }).to eq(%w[next-release-prepare next-release-cut])
    expect([ prepare, cut ].map { |job| job.dig("concurrency", "cancel-in-progress") }).to all(be(false))
  end
end
