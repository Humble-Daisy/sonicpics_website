require "rails_helper"

RSpec.describe "Deleting a project resource", type: :system do
  let(:author) { create(:user) }
  let(:workspace) { author.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: author) }
  let!(:resource) { create(:resource, project: project, created_by: author, title: "Kickoff notes") }
  let(:axe_options) { { runOnly: { type: "tag", values: [ "wcag2aaa" ] } } }

  context "as the resource's author" do
    before { sign_in_via_form(author) }

    it "deletes it from its page, through a confirm dialog" do
      visit workspace_project_resource_path(workspace, project, resource)
      click_button I18n.t("workspaces.projects.resources.show.delete")
      expect(page).to have_css("dialog[open]")
      expect(page).to have_text(I18n.t("workspaces.projects.resources.destroy.confirm"))

      within("dialog[open]") { click_button I18n.t("workspaces.projects.resources.destroy.confirm_action") }

      expect(page).to have_current_path(workspace_project_resources_path(workspace, project))
      expect(page).to have_text("Resource deleted.")
      expect(page).to have_no_link("Kickoff notes")
      expect(resource.reload).to be_discarded
    end

    it "passes axe AAA with the delete dialog open, both themes" do
      visit workspace_project_resource_path(workspace, project, resource)
      click_button I18n.t("workspaces.projects.resources.show.delete")
      expect(page).to have_css("dialog[open]")

      expect(axe_clean_in_both_themes?(axe_options)).to be(true),
        "Accessibility violations:\n#{axe_violations_in_both_themes(axe_options).join("\n")}"
    end
  end

  context "as a project viewer who did not write it" do
    let(:viewer) { create(:user) }

    before do
      create(:membership, user: viewer, workspace: workspace)
      create(:project_membership, :viewer, project: project, user: viewer)
      sign_in_via_form(viewer)
    end

    it "offers no Delete" do
      visit workspace_project_resource_path(workspace, project, resource)

      expect(page).to have_css("h1", text: "Kickoff notes")
      expect(page).to have_no_button(I18n.t("workspaces.projects.resources.show.delete"))
    end
  end

  # destroy? grants manage_workspace, update? does not: an owner who only views can delete but not edit.
  context "as a workspace owner viewing someone else's resource" do
    let(:owner) { create(:user) }

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
      create(:project_membership, :viewer, project: project, user: owner)
      sign_in_via_form(owner)
    end

    it "offers Delete but not Edit" do
      visit workspace_project_resource_path(workspace, project, resource)

      expect(page).to have_css("h1", text: "Kickoff notes")
      expect(page).to have_button(I18n.t("workspaces.projects.resources.show.delete"))
      expect(page).to have_no_link(I18n.t("workspaces.projects.resources.show.edit"))
    end
  end
end
