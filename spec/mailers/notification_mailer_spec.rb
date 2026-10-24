require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  # WCAG 2.2 AAA — screen-reader and preview-pane skim:
  # The H1 in an HTML email must describe the email's PURPOSE, not the
  # recipient's name. Greetings live in a <p> below the H1. The text/plain
  # part should mirror the same heading-first ordering for parity.

  describe "#workspace_role_changed" do
    let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
    let(:workspace) { create(:workspace, name: "Acme") }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }
    let(:membership) { create(:membership, user: user, workspace: workspace, role: admin_role) }

    let(:mail) do
      described_class.with(
        notification: nil,
        recipient: user,
        record: membership
      ).workspace_role_changed
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.workspace_role_changed.heading", workspace_name: "Acme")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      # And the H1 must NOT be the greeting (recipient-name-first is wrong for skim).
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Ada,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Ada")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end
  end

  describe "#workspace_invitation_expiring_soon" do
    let(:workspace) { create(:workspace, name: "Globex") }
    let(:inviter) { create(:user) }
    let(:user) { create(:user, email_address: "grace@example.com", first_name: "Grace") }
    let(:invitation) do
      create(:invitation,
             invitable: workspace,
             email: user.email_address,
             invited_by: inviter,
             expires_at: 24.hours.from_now)
    end

    let(:mail) do
      described_class.with(
        notification: nil,
        recipient: user,
        record: invitation
      ).workspace_invitation_expiring_soon
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.workspace_invitation_expiring_soon.heading", workspace_name: "Globex")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Grace,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Grace")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end
  end

  describe "#sign_in_from_new_device" do
    # Use a real cache store so EmailRecipientThrottle's increment counts.
    around do |ex|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
    ensure
      Rails.cache = original
    end

    let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
    # Build a Noticed::Event so params[:notification].params[:os] resolves.
    let(:notification) do
      SignInFromNewDeviceNotifier.new(
        params: { user_agent: "Mozilla/5.0", os: "Macintosh" }
      )
    end

    let(:mail) do
      described_class.with(
        notification: notification,
        recipient: user,
        record: user
      ).sign_in_from_new_device
    end

    it "addresses the user's email address" do
      expect(mail.to).to eq([ "ada@example.com" ])
    end

    it "subject substitutes the OS" do
      expect(mail.subject).to eq(
        I18n.t("notification_mailer.sign_in_from_new_device.subject", os: "Macintosh")
      )
    end

    it "uses a localized purpose-driven H1, NOT the greeting" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.sign_in_from_new_device.heading")
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      expect(html).not_to match(%r{<h1[^>]*>\s*Hi Ada,?\s*</h1>}m)
    end

    it "places the greeting in a <p> below the H1" do
      html = mail.html_part.body.encoded
      h1_index = html.index("<h1")
      greeting_index = html.index("Hi Ada")
      expect(h1_index).to be_present
      expect(greeting_index).to be_present
      expect(greeting_index).to be > h1_index
    end

    it "renders the OS in the body" do
      expect(mail.html_part.body.encoded).to include("Macintosh")
      expect(mail.text_part.body.encoded).to include("Macintosh")
    end

    it "links to the connected accounts page" do
      expect(mail.html_part.body.encoded).to include(settings_connected_accounts_url)
      expect(mail.text_part.body.encoded).to include(settings_connected_accounts_url)
    end
  end

  describe "#password_locked" do
    around do |ex|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      ex.run
    ensure
      Rails.cache = original
    end

    let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }
    let(:mail) { described_class.with(notification: nil, recipient: user, record: user).password_locked }

    it "tells the holder how long password sign-in is paused, under a purpose-driven H1" do
      html = mail.html_part.body.encoded
      heading = I18n.t("notification_mailer.password_locked.heading")
      expect(mail.to).to eq([ "ada@example.com" ])
      expect(html).to match(%r{<h1[^>]*>\s*#{Regexp.escape(heading)}\s*</h1>}m)
      expect(mail.text_part.body.encoded).to include("Hi Ada", User::LOCK_DURATION.inspect)
    end

    it "links to sign-in, where an emailed link or a passkey still works" do
      expect(mail.html_part.body.encoded).to include(new_session_url)
      expect(mail.text_part.body.encoded).to include(new_session_url)
    end

    it "stops at the per-recipient throttle" do
      sent = Array.new(EmailRecipientThrottle::CAP + 1) do
        described_class.with(notification: nil, recipient: user, record: user).password_locked.to
      end
      expect(sent.last).to be_blank
    end
  end

  # A suspended user gets none of this mail, security mail included (#1132).
  describe "a suspended recipient" do
    let(:workspace) { create(:workspace, name: "Acme") }
    let(:admin_role) { Role.find_or_create_by!(slug: "admin", workspace_id: nil) { |r| r.name = "Admin" } }
    let(:suspended) { create(:user, email_address: "held@example.com", suspended_at: Time.current) }
    let(:membership) { create(:membership, user: suspended, workspace: workspace, role: admin_role) }

    it "builds no message for an ordinary notification" do
      mail = described_class.with(notification: nil, recipient: suspended, record: membership)
                            .workspace_role_changed

      expect(mail.to).to be_blank, "a workspace notification reached a suspended recipient"
    end

    it "builds no message for security mail either" do
      mail = described_class.with(notification: nil, recipient: suspended, record: suspended,
                                  ip_address: "203.0.113.1", user_agent: "probe")
                            .sign_in_from_new_device

      expect(mail.to).to be_blank, "security mail reached a suspended recipient"
    end

    it "still delivers to an active recipient" do
      active = create(:user, email_address: "ada@example.com")
      active_membership = create(:membership, user: active, workspace: workspace, role: admin_role)

      mail = described_class.with(notification: nil, recipient: active, record: active_membership)
                            .workspace_role_changed

      expect(mail.to).to eq([ active.email_address ])
    end
  end
end
