require "rails_helper"

RSpec.describe "the pull request template" do
  let(:template) { Rails.root.join(".github/PULL_REQUEST_TEMPLATE.md").read }
  let(:guide) { Rails.root.join("app/docs/developer/releasing.md").read }

  it "asks which unreleased PRs this one depends on, so they come out of a release together" do
    expect(template).to include("Depends on")
  end

  it "asks for what the specs can't show" do
    expect(template).to include("## What the specs can't show")
    expect(guide).to include("What the specs can't show")
  end

  it "asks for the PR's changelog entry as a file of its own in changelog.d" do
    expect(template).to include("`changelog.d/`")
  end

  it "asks the author to keep the PR removable from a release" do
    expect(template).to match(/removable/i)
    expect(guide).to include("### Keep each PR removable")
  end

  it "keeps the checklist in one list" do
    checklist = template[/^## Checklist\n\n(.*?)(?=\n## )/m, 1]

    expect(checklist.strip).not_to include("\n\n")
  end

  it "keeps the guide asking for one story per PR, so each is easy to check and to pull out" do
    expect(guide).to include("**One story per PR.**")
  end
end
