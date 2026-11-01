# Where mail goes comes from ENV; how it signs in comes from credentials (smtp.user_name, smtp.password).
# Postmark and SES recipes: /docs/developer/deployment (Configure outbound mail).
module MailDelivery
  def self.smtp_settings(env = ENV, credentials = Rails.application.credentials)
    {
      address: env["SMTP_ADDRESS"],
      port: env.fetch("SMTP_PORT", "587").to_i,
      domain: env["SMTP_DOMAIN"].presence || env["RAILS_HOST"],
      user_name: credentials.dig(:smtp, :user_name),
      password: credentials.dig(:smtp, :password),
      authentication: :plain,
      enable_starttls_auto: true
    }
  end
end
