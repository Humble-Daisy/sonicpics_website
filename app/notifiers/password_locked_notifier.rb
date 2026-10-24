# frozen_string_literal: true

# Fires when failed password attempts lock an account. The sign-in page shows the
# generic failure even then, so this is how the holder learns why; `:security` bypasses DND.
class PasswordLockedNotifier < ApplicationNotifier
  category :security
  severity :danger

  deliver_by :email do |config|
    config.mailer = "NotificationMailer"
    config.method = :password_locked
    config.before_enqueue = -> { throw(:abort) unless deliver_email_now? }
    config.enqueue = true
  end

  notification_methods do
    def message
      render_safe_or_placeholder do
        I18n.t("notifications.password_locked.message",
               locale: recipient_locale,
               user_name: event.record.first_name,
               duration: User::LOCK_DURATION.inspect)
      end
    end

    def url
      Rails.application.routes.url_helpers.new_session_path
    end
  end
end
