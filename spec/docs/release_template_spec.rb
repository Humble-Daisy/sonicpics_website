require "rails_helper"

RSpec.describe "the release pull request template" do
  let(:template) { Rails.root.join(".github/PULL_REQUEST_TEMPLATE/release.md").read }
  let(:guide) { Rails.root.join("app/docs/developer/releasing.md").read }

  it "records the commit reviewed on staging" do
    expect(template).to match(/reviewed on staging/i)
  end

  it "ships with plain bin/release ship, which finds this PR and the commit staging ran" do
    expect(template).to include("```bash\nbin/release ship\n```")
  end

  it "spells the ship command's commit the same way in the script, the template and the guide" do
    script = Rails.root.join("bin/release").read
    spellings = [ script, template, guide ].flat_map { |text| text.scan(/ship <[^>]+> (<[^>]+>)/).flatten }

    expect(spellings.uniq).to eq([ "<commit reviewed on staging>" ])
  end

  it "says Then for the next step, so it can't be read as the next branch" do
    expect(Rails.root.join("bin/release").read).not_to match(/say\("Next:/)
  end

  it "calls the release branch release/<name>, as the guide does" do
    forking = Rails.root.join("app/docs/developer/forking.md").read

    expect([ template, forking ]).to all(satisfy { |text| !text.include?("release/<date>") })
  end

  it "lists what was held back, so next can restore it after the merge-back" do
    expect(template).to match(/held back/i)
  end

  it "is filled in by bin/release cut, which the guide names" do
    expect(template).to include("<!-- bin/release cut fills this")
    expect(guide).to include("bin/release cut")
  end

  it "says how to switch a ruleset off in an emergency, and back on" do
    expect(guide).to include("enforcement=disabled").and include("bin/branch-rules")
  end
end
