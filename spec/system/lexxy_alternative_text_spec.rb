# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Lexxy's alternative text dialog", type: :system do
  let(:user) { create(:user) }
  let(:workspace) { user.workspaces.sole }
  let(:project) { create(:project, workspace: workspace, created_by: user) }
  let(:blob) do
    ActiveStorage::Blob.create_and_upload!(io: Rails.root.join("spec/fixtures/files/avatar.png").open,
      filename: "canoe.png", content_type: "image/png")
  end
  # Lexxy saves the image's `url` on the tag and builds the editor image from it, so the seed does too.
  let(:document) do
    url = Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
    create(:document, body: "<p>Trip</p>#{ActionText::Attachment.from_attachable(blob, url: url).to_html}")
  end
  let!(:resource) { create(:resource, project: project, resourceable: document, created_by: user) }

  before { sign_in_via_form(user) }

  it "takes the workspace's colours, with Save as the one filled button, in both themes" do
    expect(workspace).to be_personal
    visit edit_workspace_project_resource_path(workspace, project, resource)
    find("lexxy-editor figure img").click
    find("lexxy-editor button.lexxy-attachment-toolbar__alternative-text").click
    dialog = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    computed = ->(element, property) { page.evaluate_script("getComputedStyle(arguments[0]).#{property}", element) }

    %w[light dark].each do |theme|
      set_theme(theme)
      page_save = find_button(I18n.t("workspaces.projects.resources.edit.submit"))
      expect([ theme, computed.(dialog.find_button("Save"), :backgroundColor) ]).to eq([ theme, computed.(page_save, :backgroundColor) ])
      expect([ theme, computed.(dialog.find_button("Cancel"), :backgroundColor) ]).to eq([ theme, "rgba(0, 0, 0, 0)" ])
    end
  end

  # Lexxy names the ALT button "Alternative text" (basecamp/lexxy#1304); the host renames it until that ships.
  it "names the ALT button with the word it shows (WCAG 2.5.3 Label in Name)" do
    visit edit_workspace_project_resource_path(workspace, project, resource)
    find("lexxy-editor figure img").click
    button = find("lexxy-editor button.lexxy-attachment-toolbar__alternative-text")

    expect(button[:"aria-label"]).to contain_visible_text(button.text).and include("lternative text")
  end

  it "lets an author describe an image, in an AAA dialog, and the description reaches the page" do
    visit edit_workspace_project_resource_path(workspace, project, resource)
    find("lexxy-editor figure img").click
    find("lexxy-editor button.lexxy-attachment-toolbar__alternative-text").click

    dialog = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    expect(dialog.find("textarea[aria-label='Description']").value).to eq("")
    expect_aaa_in_both_themes

    dialog.find("textarea[aria-label='Description']").fill_in(with: "A red canoe on a still lake")
    dialog.click_button("Save")
    expect(page).to have_no_css("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")

    click_button I18n.t("workspaces.projects.resources.edit.submit")
    expect(page).to have_text(I18n.t("workspaces.projects.resources.update.success"))

    visit workspace_project_resource_path(workspace, project, resource)
    expect(page).to have_css("figure.attachment img[alt='A red canoe on a still lake']")
  end

  it "reaches the dialog from the keyboard alone, through Alt+F10, and hands focus back to ALT" do
    visit edit_workspace_project_resource_path(workspace, project, resource)
    expect(page).to have_css("lexxy-editor figure img")
    find_field(I18n.t("workspaces.projects.resources.edit.title_label")).send_keys(:tab, :tab)
    editable = find("lexxy-editor [contenteditable='true']:focus")
    # Lexical takes up the Tab's caret a task later; until then it sits after the image, where Lexxy's
    # spacer paragraph shows, and Down would skip the image.
    expect(page).to have_css("lexxy-editor p.provisional-paragraph.hidden")
    editable.send_keys(:down)
    expect(page).to have_css("lexxy-editor lexxy-attachment-toolbar:not([hidden])")

    editable.send_keys([ :alt, :f10 ])
    alt_button = find("lexxy-editor button.lexxy-attachment-toolbar__alternative-text")
    expect(alt_button).to match_selector(":focus")
    alt_button.send_keys(:enter)

    description = find("lexxy-editor dialog.lexxy-alternative-text-dialog[open] textarea[aria-label='Description']")
    expect(description).to match_selector(":focus")
    description.send_keys("A red canoe on a still lake", :tab, :tab, :enter)
    expect(page).to have_no_css("lexxy-editor dialog.lexxy-alternative-text-dialog[open]")
    expect(alt_button).to match_selector(":focus")

    find_button(I18n.t("workspaces.projects.resources.edit.submit")).send_keys(:enter)
    expect(page).to have_text(I18n.t("workspaces.projects.resources.update.success"))
    visit workspace_project_resource_path(workspace, project, resource)
    expect(page).to have_css("figure.attachment img[alt='A red canoe on a still lake']")
  end
end
