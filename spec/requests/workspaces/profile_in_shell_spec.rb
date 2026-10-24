require "rails_helper"

RSpec.describe "Workspace Profile in the workspace shell", type: :request do
  let(:user) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme") }
  let!(:membership) { create(:membership, :owner, user: user, workspace: workspace) }

  before { sign_in(user) }

  it "renders in the workspace shell (primary sidebar), not the settings hub aside" do
    get edit_workspace_path(workspace)
    doc = Nokogiri::HTML(response.body)
    # Primary workspace sidebar present, with Settings marked current.
    expect(doc.at_css('aside[aria-label="' + I18n.t("workspaces.sidebar.aria_label") + '"]')).not_to be_nil
    settings_link = doc.css('a[aria-current="page"]').find { |a| a.text.include?(I18n.t("workspaces.sidebar.settings")) }
    expect(settings_link).not_to be_nil
    # The settings-hub announcer is gone from this page.
    expect(doc.at_css("#settings-aria-live")).to be_nil
  end

  it "names the logo button with the initials it shows (WCAG 2.5.3 Label in Name)" do
    get edit_workspace_path(workspace)
    button = Capybara.string(response.body).find("button:has(#workspace_logo_branding)")
    expect(button[:"aria-label"]).to be_nil
    expect(button.find(".sr-only").text).to contain_visible_text(workspace.identity.initials).and include("change logo")
  end

  it "shows the secondary sub-nav with Profile current and a distinct aria-label" do
    get edit_workspace_path(workspace)
    doc = Nokogiri::HTML(response.body)
    subnav = doc.at_css('nav[aria-label="' + I18n.t("settings.sidebar.strip_heading.workspace") + '"]')
    expect(subnav).not_to be_nil
    # Distinct from the primary sidebar's aria-label.
    expect(I18n.t("settings.sidebar.strip_heading.workspace")).not_to eq(I18n.t("workspaces.sidebar.aria_label"))
    profile_current = subnav.css('a[aria-current="page"]').find { |a| a.text.include?(I18n.t("settings.sidebar.items.profile")) }
    expect(profile_current).not_to be_nil
  end

  it "renders a mobile breadcrumb whose last crumb is the current, non-link Settings" do
    get edit_workspace_path(workspace)
    doc = Nokogiri::HTML(response.body)
    crumb = doc.at_css('nav[aria-label="Breadcrumb"] [aria-current="page"]')
    expect(crumb).not_to be_nil
    expect(crumb.name).to eq("span") # non-link
    expect(crumb.text).to include(I18n.t("workspaces.sidebar.settings"))
  end
end
