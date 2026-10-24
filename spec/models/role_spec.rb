require "rails_helper"

RSpec.describe Role, type: :model do
  describe "#owner?" do
    it "is true for the owner slug" do
      expect(build(:role, :owner).owner?).to be true
    end

    it "is false for any other slug" do
      expect(build(:role, :admin).owner?).to be false
      expect(build(:role, slug: "custom").owner?).to be false
    end
  end

  describe ".owner" do
    it "is the one definition the predicate and every owner query share" do
      owner = Role.system_default!("owner")
      Role.system_default!("admin")

      expect(Role.owner).to contain_exactly(owner)
      expect(Role.owner.all?(&:owner?)).to be(true)
    end
  end

  describe "validations" do
    it "requires a name" do
      role = build(:role, name: nil)
      expect(role).not_to be_valid
    end

    it "requires a slug" do
      role = build(:role, slug: nil)
      expect(role).not_to be_valid
    end

    it "enforces unique slug per workspace" do
      workspace = create(:workspace)
      create(:role, slug: "custom", workspace: workspace)
      duplicate = build(:role, slug: "custom", workspace: workspace)
      expect(duplicate).not_to be_valid
    end

    it "allows same slug in different workspaces" do
      create(:role, slug: "custom", workspace: create(:workspace))
      other = build(:role, slug: "custom", workspace: create(:workspace))
      expect(other).to be_valid
    end

    describe "permissions shape" do
      it "accepts an empty hash" do
        expect(build(:role, permissions: {})).to be_valid
      end

      it "accepts valid string-key boolean-value hash" do
        role = build(:role, permissions: { "manage_workspace" => true, "custom_perm" => false })
        expect(role).to be_valid
      end

      # `details` proves the symbol contract; the literal proves a human
      # sentence actually reached the user. Asserting `I18n.t(same_key)` here
      # would put the same lookup on both sides of the expectation.
      it "rejects non-hash permissions" do
        role = build(:role, permissions: "invalid")
        expect(role).not_to be_valid
        expect(role.errors.details[:permissions]).to include(error: :not_a_hash)
        expect(role.errors[:permissions]).to include("must be a hash")
      end

      it "rejects non-boolean values" do
        role = build(:role, permissions: { "manage_workspace" => "yes" })
        expect(role).not_to be_valid
        expect(role.errors.details[:permissions]).to include(error: :non_boolean_value)
        expect(role.errors[:permissions]).to include("values must be booleans")
      end

      it "coerces non-string keys to strings via JSON serialization" do
        role = build(:role, permissions: { 123 => true })
        expect(role).to be_valid
        expect(role.permissions.keys).to all(be_a(String))
      end
    end
  end

  describe "global role uniqueness (workspace_id IS NULL)" do
    # The partial index on slug WHERE workspace_id IS NULL is the invariant (NULLs
    # escape the composite index); find_or_create: the roles may be seeded — see #434.
    it "rejects a duplicate global slug at the database level" do
      Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      duplicate = build(:role, slug: "owner", workspace: nil)
      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe ".system_default!" do
    it "returns the existing global role without creating another" do
      existing = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      result = nil
      expect { result = Role.system_default!("owner") }.not_to change(Role, :count)
      expect(result).to eq(existing)
    end

    it "creates the role with canonical name and permissions when missing" do
      # CI's seeded baseline includes the global roles; the "missing" case must
      # be arranged explicitly (rolled back with the example transaction).
      Role.where(slug: "member", workspace_id: nil).delete_all
      role = Role.system_default!(:member)
      expect(role).to be_persisted
      expect(role.workspace_id).to be_nil
      expect(role.name).to eq("Member")
      expect(role.permissions).to include("manage_projects" => true)
    end

    it "raises KeyError for a slug with no canonical definition" do
      expect { Role.system_default!("superuser") }.to raise_error(KeyError)
    end

    it "returns the winner's row when losing the insert race" do
      existing = Role.find_or_create_by!(slug: "owner", workspace_id: nil) { |r| r.name = "Owner" }
      # find_or_create_by!'s find-then-create window can't be opened in
      # single-threaded SQLite; simulate losing the race by forcing the
      # create path into the partial unique index.
      allow(Role).to receive(:find_or_create_by!).and_raise(ActiveRecord::RecordNotUnique)
      expect(Role.system_default!("owner")).to eq(existing)
    end
  end

  describe "system defaults" do
    let!(:default_roles) do
      Role::SYSTEM_DEFAULTS.each_key { |slug| Role.system_default!(slug) }
    end

    it "has 4 default roles" do
      expect(Role.where(workspace_id: nil).count).to eq(4)
    end

    %w[owner admin member viewer].each do |slug|
      it "has #{slug} role" do
        expect(Role.find_by(slug: slug, workspace_id: nil)).to be_present
      end
    end

    it "owner has manage_workspace permission" do
      owner = Role.find_by(slug: "owner")
      expect(owner.permissions).to include("manage_workspace" => true)
    end
  end
end
