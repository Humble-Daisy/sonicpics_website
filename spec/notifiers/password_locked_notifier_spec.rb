# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasswordLockedNotifier, type: :notifier do
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper

  let(:user) { create(:user, email_address: "ada@example.com", first_name: "Ada") }

  before { ActionMailer::Base.deliveries.clear }

  it "emails the holder, who is signed out and never sees the in-app notice" do
    described_class.with(record: user).deliver(user)
    drain_noticed_jobs(deliver_mail: true)

    mail = ActionMailer::Base.deliveries.sole
    expect(mail.to).to eq([ "ada@example.com" ])
    expect(mail.subject).to eq(I18n.t("notification_mailer.password_locked.subject"))
    expect(mail.text_part.body.to_s).to include("Ada", User::LOCK_DURATION.inspect)
    expect(mail.html_part.body.to_s).to include(Rails.application.routes.url_helpers.new_session_path)
  end

  it "still emails under quiet hours, since a lock is a security alert" do
    prefs = create(:user_preferences, user: user)
    prefs.update!(notification_preferences:
      prefs.notification_preferences.merge("quiet_hours" => { "enabled" => true, "start" => "00:00", "end" => "23:59", "allow_urgent" => true }))

    described_class.with(record: user).deliver(user)
    drain_noticed_jobs(deliver_mail: true)

    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([ [ "ada@example.com" ] ])
  end
end
