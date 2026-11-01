require "rails_helper"
require "yaml"
require "kamal"

RSpec.describe "the deploy workflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/deploy.yml"), aliases: true) }
  let(:triggers) { workflow[true] || workflow["on"] }
  let(:job) { workflow.dig("jobs", "deploy") }

  it "deploys on a push to main or a release branch, and on nothing else" do
    expect(triggers.keys).to eq([ "push" ])
    expect(triggers.dig("push", "branches")).to contain_exactly("main", "release/**")
  end

  it "stays off for each environment until its repository variable says true" do
    expect(job["if"]).to include("vars.DEPLOY_PRODUCTION == 'true'").and include("vars.DEPLOY_STAGING == 'true'")
  end

  it "names the GitHub environment, so its secrets and deployment record follow the branch" do
    expect(job["environment"]).to include("production").and include("staging")
  end

  it "never cancels a deploy in flight" do
    expect(workflow.dig("concurrency", "cancel-in-progress")).to be(false)
  end

  it "deploys staging as the staging destination and production as the default" do
    deploy_step = job["steps"].find { |step| step["run"].to_s.include?("bin/kamal deploy") }

    expect(deploy_step["run"]).to include("-d staging")
  end
end

RSpec.describe "config/deploy.staging.yml" do
  let(:staging) do
    Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"), destination: "staging", version: "spec")
  end
  let(:production) { Kamal::Configuration.create_from(config_file: Rails.root.join("config/deploy.yml"), version: "spec") }

  it "decrypts the staging credentials, since staging runs RAILS_ENV=production" do
    expect(staging.env.clear).to include("RAILS_CREDENTIALS_ENV" => "staging")
    expect(production.env.clear).not_to have_key("RAILS_CREDENTIALS_ENV")
  end

  it "keeps its SQLite databases in a volume of its own, even on production's host" do
    expect(staging.volume_args).not_to eq(production.volume_args)
  end
end
