require "rails_helper"
require "rake"

RSpec.describe "operators rake tasks" do
  before(:all) { RakeTasks.load_once }

  describe "operators:grant" do
    it "grants an operatorship with no granter and writes the audit row" do
      user = create(:user)

      expect { RakeTasks.invoke("operators:grant", user.email_address) }
        .to change { user.reload.operator? }.from(false).to(true)
        .and change { ActivityLog.where(action: "operatorship.granted").count }.by(1)

      expect(user.operatorships.kept.sole.granted_by_id).to be_nil
      expect(ActivityLog.where(action: "operatorship.granted").order(:id).last.actor_id).to be_nil
    end

    it "is idempotent for an existing operator" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { RakeTasks.invoke("operators:grant", user.email_address) }
        .to change(Operatorship, :count).by(0)
        .and change(ActivityLog, :count).by(0)
    end

    it "aborts on an unknown email" do
      expect { RakeTasks.invoke("operators:grant", "nobody@example.com") }.to raise_error(SystemExit)
    end

    # An operator typed the address on the command line — the same vouching
    # the :shared seed does for its bootstrap owner — so the account can do
    # the first thing an operator exists to do: send an invitation.
    it "vouches for the address so the new operator can invite" do
      user = create(:user, :no_authentications)
      expect(user.can_invite?).to be(false)

      RakeTasks.invoke("operators:grant", user.email_address)

      auth = user.authentications.email.sole
      expect(auth.email).to eq(user.email_address)
      expect(auth.verified_at).to be_present
      expect(user.reload.can_invite?).to be(true)
    end

    it "vouches for an existing operator granted before the row existed" do
      user = create(:user, :no_authentications)
      Operatorship.grant!(user: user)

      expect { RakeTasks.invoke("operators:grant", user.email_address) }
        .to change { user.reload.can_invite? }.from(false).to(true)
    end

    # The seed's precedent: vouching creates a row; it never converts a
    # pending round-trip into a verified one.
    it "leaves an existing pending email authentication pending" do
      user = create(:user, :no_authentications)
      user.authentications.create!(provider: "email", email: user.email_address)

      RakeTasks.invoke("operators:grant", user.email_address)

      expect(user.authentications.email.sole).to be_pending
      expect(user.reload.can_invite?).to be(false)
    end
  end

  describe "operators:revoke" do
    it "revokes and writes the audit row" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { RakeTasks.invoke("operators:revoke", user.email_address) }
        .to change { user.reload.operator? }.from(true).to(false)
        .and change { ActivityLog.where(action: "operatorship.revoked").count }.by(1)
    end
  end

  describe "operators:list" do
    it "prints each kept operator's email" do
      user = create(:user)
      Operatorship.grant!(user: user)

      expect { RakeTasks.invoke("operators:list") }.to output(/#{Regexp.escape(user.email_address)}/).to_stdout
    end
  end
end
