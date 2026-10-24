# frozen_string_literal: true

require "rails_helper"

# A personal workspace configures itself through the same Profile page an org
# does. It used to have a bespoke "Customize" modal on the Overview holding the
# same two fields; this file is that spec, repointed at the shared route, so the
# behaviour it guarded (rename, logo trigger, identity picker, AAA with the
# picker open) is still covered after the two shapes were unified.
RSpec.describe "Personal workspace Profile", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.kept.sole }

  before { sign_in_via_form(user) }

  it "renames the workspace and reflects it in the sidebar switcher" do
    visit edit_workspace_path(workspace)

    fill_in I18n.t("workspaces.edit.name_label"), with: "My Stuff"
    click_on I18n.t("workspaces.settings.edit.sections.identity_submit")

    expect(page).to have_css("#workspace-name-heading", text: "My Stuff")
  end

  it "exposes the logo-picker trigger" do
    visit edit_workspace_path(workspace)

    expect(page).to have_css("button:has(#workspace_logo_branding)")
  end

  it "opens the identity-picker dialog from the logo trigger" do
    visit edit_workspace_path(workspace)

    find("button:has(#workspace_logo_branding)").click

    # The hub turbo frame loads its source-selection radiogroup.
    expect(page).to have_css("#identity-picker-hub [role='radiogroup']", wait: 10)
    expect(page).to have_text(I18n.t("identity_picker.choose_workspace_logo"))
  end

  it "passes the AAA axe check with the identity picker open, both themes" do
    visit edit_workspace_path(workspace)

    find("button:has(#workspace_logo_branding)").click
    expect(page).to have_css("#identity-picker-hub [role='radiogroup']", wait: 10)

    expect(axe_clean_in_both_themes?).to(
      be(true),
      axe_violations_in_both_themes.join("\n")
    )
  end
end
