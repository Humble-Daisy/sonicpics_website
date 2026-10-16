require "rails_helper"

# Workspace Profile destination — the new home for identity edits (name,
# logo, primary_color) after the settings hub route consolidation. Posts to
# workspaces#update; gated by Workspaces::ProfilePolicy (manage_settings).
RSpec.describe "Workspace Profile destination", type: :system do
  let(:owner) { create(:user) }
  let(:workspace) { create(:workspace, name: "Acme Corp") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  before do
    create(:membership, :owner, user: owner, workspace: workspace)
    sign_in_via_form(owner)
  end

  it "renders the Profile H1, disambiguated by the persistent identity bar" do
    visit edit_workspace_path(workspace)
    expect(page).to have_css("h1", text: "Profile")
    expect(page).to have_css("#workspace-name-heading", text: workspace.name)
  end

  it "renders the Profile description" do
    visit edit_workspace_path(workspace)
    expect(page).to have_text(I18n.t("settings.pages.workspace_profile.description"))
  end

  it "saves the name" do
    visit edit_workspace_path(workspace)

    fill_in I18n.t("workspaces.edit.name_label"), with: "Acme Limited"
    click_on I18n.t("workspaces.settings.edit.sections.identity_submit")

    expect(page).to have_css("#workspace-name-heading", text: "Acme Limited")
    expect(workspace.reload.name).to eq("Acme Limited")
  end

  # The identity picker renders its own <form>. Nested inside the name form, the
  # parser ignores its start tag but honours its </form>, closing the OUTER form
  # and orphaning every later control — the Save button included, so the name
  # silently would not save. Measured, not assumed: this asserts the DOM the
  # browser actually built.
  it "leaves no submit control outside a form" do
    visit edit_workspace_path(workspace)

    orphans = page.evaluate_script(<<~JS)
      [...document.querySelectorAll("input[type=submit], button[type=submit]")]
        .filter(s => !s.closest("form"))
        .map(s => s.value || s.textContent.trim())
    JS

    expect(orphans).to be_empty,
      "submit controls outside any form (nested-form parse break): #{orphans.inspect}"
  end

  it "passes axe-core at WCAG 2.2 AAA in light and dark modes" do
    visit edit_workspace_path(workspace)
    expect(axe_clean_in_both_themes?(axe_options)).to be(true),
      "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
  end

  describe "removing the logo (#1402)" do
    let(:workspace) { create(:workspace, :with_logo, name: "Acme Corp") }

    it "removes the logo and keeps the workspace" do
      visit edit_workspace_path(workspace)
      open_identity_picker
      enter_crop_view

      remove_photo_expecting_modal_close

      expect(page).to have_current_path(edit_workspace_path(workspace))
      expect(page).to have_css("#workspace-name-heading", text: "Acme Corp")
      workspace.reload
      expect(workspace.discarded_at).to be_nil
      expect(workspace.logo_source).to eq("initials")
      expect(workspace.logo).not_to be_attached
      expect(workspace.logo_original).not_to be_attached
    end
  end
end
