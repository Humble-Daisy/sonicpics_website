require "rails_helper"
require "nokogiri"
require "release_flow"

RSpec.describe "The releasing guide" do
  let(:source) { Rails.root.join("app/docs/developer/releasing.md").read }
  let(:rendered) { Nokogiri::HTML5.fragment(Markdowndocs::MarkdownRenderer.render(source.sub(/\A---\n.*?\n---\n/m, ""))) }
  let(:before_it_merges) { source[/^## Before it merges\n.*?(?=^## )/m] }

  it "sends every in-page link to a heading that exists" do
    ids = rendered.css("[id]").map { |node| node["id"] }

    rendered.css('a[href^="#"]').each do |link|
      expect(ids).to include(link["href"].delete_prefix("#")), "#{link["href"]} has no heading"
    end
  end

  it "asks for the PR's changelog line before it merges, not only at release time" do
    expect(before_it_merges).to include("changelog.d/")
  end

  it "says the cut runs when CI finishes on next, failed or passed, so a red run is reported" do
    expect(source).to include("| `next_release.yml` | CI finishes on a push to `next` |")
  end

  it "names every setting .release_flow.yml takes, so a repository with other names can use the flow" do
    section = source[/^## Changing the flow\n.*\z/m].to_s

    expect(section).to include("`.release_flow.yml`")
    ReleaseFlow::DEFAULTS.each_key { |setting| expect(section).to include("`#{setting}`") }
  end

  it "has changelog.d's README send a fix for the release under review to that release's section" do
    readme = Rails.root.join("changelog.d/README.md").read

    expect(readme).to include("## v<name>").and match(/release under review/)
  end

  it "shows how to hold back a squash-merged PR as well as a merged one" do
    expect(source).to include("git revert -m 1 <the feature's merge commit>").and include("git revert <its squash commit>")
  end

  it "says what a hotfix ships without: a tag" do
    expect(source[/^## Hotfix\n.*?(?=^## )/m]).to match(/untagged/)
  end

  it "maps what makes the flow run: the script, the workflows, the PR features and the switches" do
    section = source[/^## What makes it run\n.*?(?=^## )/m].to_s

    %w[bin/release ci.yml deploy.yml next_release.yml bin/branch-rules
       AUTO_RELEASE RELEASE_TOKEN DEPLOY_STAGING DEPLOY_PRODUCTION].each do |lever|
      expect(section).to include(lever), "#{lever} is missing from What makes it run"
    end
  end

  it "lists every workflow bin/release reads among the files to change together" do
    changing = source[/^## Changing the flow\n.*/m]

    Rails.root.join("bin/release").read.scan(/[\w-]+\.yml/).uniq.each do |workflow|
      expect(changing).to include(workflow)
    end
  end

  it "gives commands that run as written, with no placeholder for the repository" do
    expect(source).not_to include("OWNER/REPO")
  end
end
