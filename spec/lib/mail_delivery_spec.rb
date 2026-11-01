require "rails_helper"
require "mail_delivery"

RSpec.describe MailDelivery do
  let(:env) { { "RAILS_HOST" => "app.humbledaisy.com", "SMTP_ADDRESS" => "smtp.postmarkapp.com" } }
  let(:credentials) { { smtp: { user_name: "token", password: "token" } } }

  describe ".smtp_settings" do
    it "reads the server from the environment and the login from credentials" do
      expect(described_class.smtp_settings(env, credentials)).to include(
        address: "smtp.postmarkapp.com", user_name: "token", password: "token", authentication: :plain
      )
    end

    it "no longer takes the login from the environment" do
      settings = described_class.smtp_settings(env.merge("SMTP_USERNAME" => "old", "SMTP_PASSWORD" => "old"), {})

      expect(settings).to include(user_name: nil, password: nil)
    end

    it "defaults the port to submission and the HELO domain to RAILS_HOST" do
      expect(described_class.smtp_settings(env, credentials)).to include(port: 587, domain: "app.humbledaisy.com")
    end

    it "takes an explicit port and domain" do
      settings = described_class.smtp_settings(
        env.merge("SMTP_PORT" => "2525", "SMTP_DOMAIN" => "mail.humbledaisy.com"), credentials
      )

      expect(settings).to include(port: 2525, domain: "mail.humbledaisy.com")
    end
  end
end
