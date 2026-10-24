# frozen_string_literal: true

require "rails_helper"

# #461: the mailer layout has its own inline palette (MailerTheme), outside the
# token system the axe gate validates, so no mail had ever been audited. Every
# mailer action is rendered here with real records, its HTML part loaded into
# the browser as the document, and audited at the same AAA rule set as pages.
# One theme: mail carries its own colours. `exclude: []` — nothing deferred.
RSpec.describe "Mailer templates", type: :system do
  let(:user) { create(:user, first_name: "Ada", email_address: "ada@example.com") }
  let(:workspace) { create(:workspace, name: "Acme") }

  def load_mail(mail)
    html = mail.html_part ? mail.html_part.body.decoded : mail.body.decoded
    visit "about:blank"
    frame_id = cdp_command("Page.getFrameTree").dig("frameTree", "frame", "id")
    cdp_command("Page.setDocumentContent", frameId: frame_id, html: html)
  end

  def deliver_in_app(notifier, record, recipient)
    notifier.with(record: record).deliver(recipient)
    recipient.notifications.order(:id).last
  end

  mails = {
    "AuthenticationMailer#verification_email" => -> {
      bare = create(:user, :no_authentications, first_name: "Ada", email_address: "ada2@example.com")
      AuthenticationMailer.verification_email(create(:authentication, user: bare, verified_at: nil))
    },
    "AuthenticationMailer#email_change_verification" => -> {
      user.update!(pending_email: "ada.new@example.com")
      AuthenticationMailer.email_change_verification(user)
    },
    "AuthenticationMailer#email_change_notification" => -> {
      user.update!(pending_email: "ada.new@example.com")
      AuthenticationMailer.email_change_notification(user)
    },
    "AuthenticationMailer#link_verification_email" => -> {
      bare = create(:user, :no_authentications, first_name: "Ada", email_address: "ada3@example.com")
      AuthenticationMailer.link_verification_email(create(:authentication, user: bare, verified_at: nil))
    },
    "AuthenticationMailer#collision_alert" => -> { AuthenticationMailer.collision_alert(user, "Google") },
    "MagicLinkMailer#sign_in_link" => -> { MagicLinkMailer.sign_in_link(user.email_address, "token") },
    "MagicLinkMailer#registration_link" => -> { MagicLinkMailer.registration_link("new@example.com", "token") },
    "ReauthenticationMailer#code" => -> { ReauthenticationMailer.code(user, "123456") },
    "InvitationMailer#invite" => -> {
      InvitationMailer.with(invitation: create(:invitation, invitable: workspace, email: "invitee@example.com")).invite
    },
    "InvitationMailer#invite_client" => -> {
      project = create(:project, workspace: workspace, clientside_enabled: true)
      InvitationMailer.with(invitation: create(:invitation, :client, invitable: project, email: "dana@bigco.com")).invite_client
    },
    "NotificationMailer#workspace_role_changed" => -> {
      membership = create(:membership, user: user, workspace: workspace)
      NotificationMailer.with(notification: nil, recipient: user, record: membership).workspace_role_changed
    },
    "NotificationMailer#workspace_invitation_expiring_soon" => -> {
      invitation = create(:invitation, invitable: workspace, email: "invitee@example.com", expires_at: 24.hours.from_now)
      NotificationMailer.with(notification: nil, recipient: user, record: invitation).workspace_invitation_expiring_soon
    },
    "NotificationMailer#workspace_member_added" => -> {
      membership = create(:membership, user: user, workspace: workspace)
      NotificationMailer.with(notification: nil, recipient: user, record: membership).workspace_member_added
    },
    "NotificationMailer#workspace_member_removed" => -> {
      membership = create(:membership, user: user, workspace: workspace)
      NotificationMailer.with(notification: nil, recipient: user, record: membership).workspace_member_removed
    },
    "NotificationMailer#workspace_capacity_approaching" => -> {
      NotificationMailer.with(notification: nil, recipient: user, record: workspace).workspace_capacity_approaching
    },
    "NotificationMailer#sign_in_from_new_device" => -> {
      SignInFromNewDeviceNotifier.with(record: user, user_agent: "Mozilla/5.0 (Macintosh) Safari/605.1", os: "macOS").deliver(user)
      notification = user.notifications.order(:id).last
      NotificationMailer.with(notification: notification, recipient: user, record: user).sign_in_from_new_device
    },
    "NotificationMailer#password_locked" => -> {
      NotificationMailer.with(notification: nil, recipient: user, record: user).password_locked
    },
    "NotificationMailer#digest" => -> {
      membership = create(:membership, user: user, workspace: workspace)
      notification = deliver_in_app(WorkspaceMemberAddedNotifier, membership, user)
      NotificationMailer.digest(user, [ notification ])
    }
  }

  mails.each do |name, build|
    it "#{name} passes the AAA audit" do
      load_mail(instance_exec(&build))
      violations = axe_violations(exclude: [])
      expect(violations).to be_empty, violations.join("\n")
    end
  end
end
