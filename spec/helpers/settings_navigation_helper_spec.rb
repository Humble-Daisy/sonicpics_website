require "rails_helper"

RSpec.describe SettingsNavigationHelper, type: :helper do
  it "names every item with the words it shows (WCAG 2.5.3 Label in Name)" do
    workspace = create(:workspace)
    owner = create(:user)
    create(:membership, :owner, user: owner, workspace: workspace)
    allow(Current).to receive_messages(user: owner, workspace: workspace)
    allow(helper).to receive(:current_page?).and_return(false)

    items = helper.workspace_settings_nav_items + helper.identity_settings_nav_items
    items.select { |item| item[:aria_label] }.each do |item|
      expect(item[:aria_label]).to contain_visible_text(item[:label])
    end
  end

  describe "#workspace_settings_nav_items" do
    let(:workspace) { create(:workspace) }
    let(:owner) { create(:user) }

    before do
      create(:membership, :owner, user: owner, workspace: workspace)
      allow(Current).to receive(:user).and_return(owner)
      allow(Current).to receive(:workspace).and_return(workspace)
      # current_page? is provided by the view context in a helper spec; stub it false.
      allow(helper).to receive(:current_page?).and_return(false)
    end

    it "returns Profile, Members, Limits & Plan for an owner" do
      labels = helper.workspace_settings_nav_items.map { |i| i[:label] }
      expect(labels).to eq([
        I18n.t("settings.sidebar.items.profile"),
        I18n.t("settings.sidebar.items.members"),
        I18n.t("settings.sidebar.items.limits_and_plan")
      ])
    end

    it "each item carries href + icon and gating is applied (no Limits & Plan for a member)" do
      member = create(:user)
      create(:membership, user: member, workspace: workspace) # non-owner
      allow(Current).to receive(:user).and_return(member)

      items = helper.workspace_settings_nav_items
      expect(items).to all(include(:href, :icon))
      labels = items.map { |i| i[:label] }
      expect(labels).not_to include(I18n.t("settings.sidebar.items.limits_and_plan"))
    end
  end

  describe "#identity_settings_nav_items" do
    before { allow(helper).to receive(:current_page?).and_return(false) }

    it "returns the account items in order" do
      labels = helper.identity_settings_nav_items.map { |i| i[:label] }
      expect(labels).to eq([
        I18n.t("settings.sidebar.items.profile"),
        I18n.t("settings.sidebar.items.notifications"),
        I18n.t("settings.sidebar.items.security"),
        I18n.t("settings.sidebar.items.passkeys"),
        I18n.t("settings.sidebar.items.invitation_blocks"),
        I18n.t("settings.sidebar.items.sessions"),
        I18n.t("settings.sidebar.items.appearance")
      ])
    end
  end
end
