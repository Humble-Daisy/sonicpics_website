require "rails_helper"

# User::Onboarding's examples. A concern trait is not instantiated, so its
# examples describe the model; this file is scoped by directory to the trait.
RSpec.describe User, type: :model do
  describe "personal workspace" do
    it "creates a personal workspace on sign-up" do
      user = create(:user)
      expect(user.workspaces.count).to eq(1)
      expect(user.workspaces.first.name).to include(user.first_name)
    end

    it "assigns owner role to personal workspace" do
      user = create(:user)
      membership = user.memberships.first
      expect(membership.role.slug).to eq("owner")
    end
  end

  describe "#personal_workspace" do
    let(:user) { create(:user) }

    it "returns the workspace pointed to by personal_workspace_id" do
      expect(user.personal_workspace).to eq(Workspace.find(user.personal_workspace_id))
    end

    it "returns nil if the personal workspace has been soft-deleted" do
      # discard! now raises HomeWorkspaceProtectedError for a personal workspace, so set
      # the tombstone directly — this exercises the defensive nil-return for a
      # legacy/console-discarded personal workspace row, which is the case this
      # guard is here to survive.
      user.personal_workspace.update_column(:discarded_at, Time.current)
      expect(user.personal_workspace).to be_nil
    end

    it "returns nil if personal_workspace_id is unset" do
      user.update_column(:personal_workspace_id, nil)
      expect(user.personal_workspace).to be_nil
    end
  end

  describe "#create_personal_workspace (idempotency + uniqueness)" do
    let(:user) { create(:user) }

    it "is idempotent when called a second time on the same user" do
      original_id = user.personal_workspace_id
      expect(original_id).to be_present

      expect { user.create_personal_workspace }
        .not_to change { user.reload.personal_workspace_id }
      expect(user.personal_workspace_id).to eq(original_id)
    end

    it "enforces uniqueness at the database level" do
      other_user = create(:user)
      # Try to point two users at the same personal workspace — the partial
      # unique index on personal_workspace_id (where IS NOT NULL) must reject.
      expect {
        other_user.update_column(:personal_workspace_id, user.personal_workspace_id)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "#onboard_workspace under :shared posture" do
    let!(:shared_workspace) { create(:workspace, slug: "acme", name: "Acme", personal: false) }

    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return(shared_workspace.slug)
    end

    it "joins the configured shared workspace instead of creating a personal one" do
      user = create(:user)

      expect(user.personal_workspace_id).to be_nil
      expect(user.workspaces).to contain_exactly(shared_workspace)
    end

    it "joins as a Member (not Owner)" do
      user = create(:user)

      membership = shared_workspace.memberships.find_by!(user: user)
      expect(membership.role.slug).to eq("member")
    end

    it "raises when the configured shared workspace doesn't exist" do
      allow(Rails.configuration.x.tenancy).to receive(:shared_workspace_slug).and_return("missing")

      expect { create(:user) }.to raise_error(/shared workspace/i)
    end

    it "creates the account but joins no membership when the shared workspace is suspended" do
      shared_workspace.suspend!

      user = nil
      expect {
        user = create(:user)
      }.to change(User, :count).by(1)

      expect(shared_workspace.memberships.where(user: user)).to be_empty
    end
  end

  describe "#onboard_workspace under :none posture" do
    before do
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:none)
    end

    it "creates no workspace on sign-up" do
      user = create(:user)
      expect(user.workspaces).to be_empty
      expect(user.memberships).to be_empty
    end

    it "assigns no personal_workspace_id" do
      user = create(:user)
      expect(user.personal_workspace_id).to be_nil
      expect(user.personal_workspace).to be_nil
    end

    it "dispatches to an explicit no-op (does not call create_personal_workspace)" do
      expect_any_instance_of(User).not_to receive(:create_personal_workspace)
      expect_any_instance_of(User).not_to receive(:join_shared_workspace)
      create(:user)
    end
  end

  describe "factory trait :with_zero_workspaces" do
    it "builds a user with no workspaces and no personal_workspace_id" do
      user = create(:user, :with_zero_workspaces)
      expect(user.workspaces).to be_empty
      expect(user.memberships).to be_empty
      expect(user.personal_workspace_id).to be_nil
    end

    it "still produces a persisted, valid user" do
      user = create(:user, :with_zero_workspaces)
      expect(user).to be_persisted
      expect(user).to be_valid
    end

    # Under a stub the trait cannot do what it says, and restoring through the stubbed reader
    # writes the stub's value into the real config for every later example.
    it "refuses to run while tenancy onboarding is stubbed, and leaves the real config alone" do
      real = Rails.configuration.x.tenancy[:onboarding]
      allow(Rails.configuration.x.tenancy).to receive(:onboarding).and_return(:shared)

      expect { create(:user, :with_zero_workspaces) }.to raise_error(/stubbed/)
      expect(Rails.configuration.x.tenancy[:onboarding]).to eq(real)
    end
  end

  describe "#onboarded?" do
    it "is false when onboarded_at is nil" do
      expect(build(:user, onboarded_at: nil).onboarded?).to be(false)
    end

    it "is true when onboarded_at is set" do
      expect(build(:user, onboarded_at: Time.current).onboarded?).to be(true)
    end
  end

  describe "onboarding step derivation (:none wizard)" do
    let(:owner_role) do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) do |r|
        r.name = "Owner"
        r.permissions = { manage_workspace: true, manage_members: true, manage_projects: true, manage_settings: true }
      end
    end

    def join(user, workspace)
      workspace.memberships.create!(user: user, role: owner_role)
      user.reload
    end

    it "#onboarding_workspace returns the first kept workspace, or nil when there is none" do
      user = create(:user, :with_zero_workspaces)
      expect(user.onboarding_workspace).to be_nil

      workspace = create(:workspace)
      join(user, workspace)
      expect(user.onboarding_workspace).to eq(workspace)
    end

    it "#onboarding_step is :workspace when the user has no workspace" do
      user = create(:user, :with_zero_workspaces)
      expect(user.onboarding_step).to eq(:workspace)
    end

    it "#onboarding_step is :project with a workspace but no project" do
      user = create(:user, :with_zero_workspaces)
      join(user, create(:workspace))
      expect(user.onboarding_step).to eq(:project)
    end

    it "#onboarding_step is :team with a workspace that has a project" do
      user = create(:user, :with_zero_workspaces)
      workspace = create(:workspace)
      join(user, workspace)
      create(:project, workspace: workspace)
      expect(user.reload.onboarding_step).to eq(:team)
    end
  end
end
