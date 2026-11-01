require "rails_helper"
require "tmpdir"

load Rails.root.join("bin/release")

# The flow itself is the release_flow gem's, and its specs cover it; this repository adds the fork's template.
RSpec.describe ForkTemplate do
  let(:root) { Pathname.new(Dir.mktmpdir) }

  after { FileUtils.rm_rf(root) }

  it "names no template outside a fork" do
    expect(described_class.config(root.to_s).template).to be_nil
  end

  it "reads a fork's template from the .fork.yml that bin/fork writes" do
    root.join(".fork.yml").write({ "name" => "app", "template_url" => "git@github.com:me/template.git" }.to_yaml)

    expect(described_class.config(root.to_s).template).to eq("me/template")
  end

  it "lets .release_flow.yml name the template instead" do
    root.join(".fork.yml").write({ "template_url" => "git@github.com:me/template.git" }.to_yaml)
    root.join(".release_flow.yml").write("template: me/other\n")

    expect(described_class.config(root.to_s).template).to eq("me/other")
  end

  it "points bin/release --help at this repository's guide" do
    output = IO.popen({ "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s },
                      [ Rails.root.join("bin/release").to_s, "--help" ], err: [ :child, :out ], &:read)

    expect(output).to include("usage: bin/release prepare").and include("(see /docs/developer/releasing)")
  end
end
