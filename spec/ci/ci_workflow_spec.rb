require "rails_helper"
require "yaml"

RSpec.describe "the CI workflow" do
  let(:workflow) { YAML.safe_load_file(Rails.root.join(".github/workflows/ci.yml"), aliases: true) }
  let(:triggers) { workflow[true] || workflow["on"] }

  it "checks every pull request, and next and main again after every merge" do
    expect(triggers.keys).to contain_exactly("pull_request", "push")
    expect(triggers.dig("push", "branches")).to contain_exactly("next", "main")
  end

  it "gives every push its own run, so each merge keeps its own result" do
    expect(workflow.dig("concurrency", "group")).to eq("ci-${{ github.workflow }}-${{ github.head_ref || github.sha }}")
    expect(workflow.dig("concurrency", "cancel-in-progress")).to eq("${{ github.event_name == 'pull_request' }}")
  end
end
