require "rails_helper"

# The initializer defines RequiredProductionConfig and calls .check! only when
# booting a real production process, so loading it here is side-effect free.
load Rails.root.join("config/initializers/required_production_config.rb").to_s unless defined?(RequiredProductionConfig)

RSpec.describe RequiredProductionConfig do
  describe ".check!" do
    let(:backups) { { "OBJECT_STORAGE_BUCKET" => "app-backups", "OBJECT_STORAGE_REGION" => "auto" } }
    let(:storage) { { object_storage: { access_key_id: "id", secret_access_key: "secret" } } }
    let(:mail) { { "SMTP_ADDRESS" => "smtp.postmarkapp.com", **backups } }
    let(:smtp) { { smtp: { user_name: "token", password: "token" }, **storage } }

    it "raises when RAILS_HOST is unset" do
      expect { described_class.check!({}) }
        .to raise_error(RuntimeError, /RAILS_HOST is unset/)
    end

    it "raises when RAILS_HOST is blank" do
      expect { described_class.check!({ "RAILS_HOST" => "  " }) }
        .to raise_error(RuntimeError, /RAILS_HOST is unset/)
    end

    it "raises on the Rails default placeholder example.com" do
      expect { described_class.check!({ "RAILS_HOST" => "example.com" }) }
        .to raise_error(RuntimeError, /"example\.com"/)
    end

    it "raises on a bin/fork .example placeholder" do
      expect { described_class.check!({ "RAILS_HOST" => "my_app.example" }) }
        .to raise_error(RuntimeError, /"my_app\.example"/)
    end

    it "raises on the .env.example sample value app.example.com" do
      expect { described_class.check!({ "RAILS_HOST" => "app.example.com" }) }
        .to raise_error(RuntimeError, /preflight failed/)
    end

    it "accepts a real hostname" do
      expect { described_class.check!({ "RAILS_HOST" => "app.humbledaisy.com", **mail }, smtp) }
        .not_to raise_error
    end

    it "accepts a hostname that merely contains the word example" do
      expect { described_class.check!({ "RAILS_HOST" => "goodexample.io", **mail }, smtp) }
        .not_to raise_error
    end

    # Sign-in is an email; a box that mails localhost:25 boots healthy and nobody can sign in (#1318).
    describe "outbound mail" do
      let(:host) { { "RAILS_HOST" => "app.humbledaisy.com" } }

      it "raises when SMTP_ADDRESS is unset" do
        expect { described_class.check!(host) }
          .to raise_error(RuntimeError, /SMTP_ADDRESS is unset/)
      end

      it "raises on localhost, where Rails mails by default" do
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "localhost")) }
          .to raise_error(RuntimeError, /"localhost"/)
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "127.0.0.1")) }
          .to raise_error(RuntimeError, /"127\.0\.0\.1"/)
      end

      it "raises on the rails new and bin/fork placeholders" do
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "smtp.example.com")) }
          .to raise_error(RuntimeError, /"smtp\.example\.com"/)
        expect { described_class.check!(host.merge("SMTP_ADDRESS" => "mail.my_app.example")) }
          .to raise_error(RuntimeError, /"mail\.my_app\.example"/)
      end

      it "raises when the address is real but the login in credentials is blank, since every send would be refused" do
        expect { described_class.check!(host.merge(mail), { smtp: { user_name: "token", password: " " } }) }
          .to raise_error(RuntimeError, /smtp\.password is unset/)
        expect { described_class.check!(host.merge(mail), {}) }
          .to raise_error(RuntimeError, /smtp\.user_name and smtp\.password are unset/)
      end

      it "no longer accepts a login from the environment" do
        expect { described_class.check!(host.merge(mail, "SMTP_USERNAME" => "token", "SMTP_PASSWORD" => "token"), {}) }
          .to raise_error(RuntimeError, /smtp\.user_name and smtp\.password are unset/)
      end

      it "names the fix and the doc in the message" do
        described_class.check!(host)
        raise "expected check! to raise"
      rescue RuntimeError => e
        expect(e.message).to include("SMTP_ADDRESS")
        expect(e.message).to include("credentials:edit --environment production")
        expect(e.message).to include("/docs/developer/deployment")
      end
    end

    it "names the fix and the opt-out in the message" do
      described_class.check!({})
      raise "expected check! to raise"
    rescue RuntimeError => e
      expect(e.message).to include("env.clear")
      expect(e.message).to include("git rm config/initializers/required_production_config.rb")
      expect(e.message).to include("/docs/developer/deployment")
    end

    # Personal data is encrypted at rest (#902); without keys the app boots,
    # /up reports healthy, and the first user read raises.
    describe "Active Record encryption keys" do
      let(:host) { { "RAILS_HOST" => "app.humbledaisy.com", **mail } }
      let(:keys) { { primary_key: "p", deterministic_key: "d", key_derivation_salt: "s" } }

      it "raises when neither credentials nor config carry the keys" do
        expect { described_class.check!(host, smtp, {}) }
          .to raise_error(RuntimeError, /active_record_encryption/)
      end

      it "names the missing key" do
        credentials = smtp.merge(active_record_encryption: keys.except(:deterministic_key))

        expect { described_class.check!(host, credentials, {}) }
          .to raise_error(RuntimeError, /deterministic_key/)
      end

      it "accepts keys from the credentials" do
        expect { described_class.check!(host, smtp.merge(active_record_encryption: keys), {}) }
          .not_to raise_error
      end

      it "accepts keys from the encryption config (the environment-variable path)" do
        expect { described_class.check!(host, smtp, keys) }
          .not_to raise_error
      end

      it "names the fix in the message" do
        described_class.check!(host, smtp, {})
        raise "expected check! to raise"
      rescue RuntimeError => e
        expect(e.message).to include("db:encryption:init")
        expect(e.message).to include("credentials:edit --environment production")
        expect(e.message).to include("/docs/developer/forking")
      end
    end

    describe "database backups" do
      let(:ready) { { "RAILS_HOST" => "app.humbledaisy.com", "SMTP_ADDRESS" => "smtp.postmarkapp.com" } }
      let(:login) { { smtp: { user_name: "token", password: "token" } } }

      it "boots with backups off, and says so in the log" do
        logger = instance_double(Logger, warn: nil)

        expect { described_class.check!(ready, login, logger: logger) }.not_to raise_error
        expect(logger).to have_received(:warn).with(/Backups are off.*BACKUP_PATH/m)
      end

      it "raises when a bucket is named without its region" do
        expect { described_class.check!(ready.merge(backups.except("OBJECT_STORAGE_REGION")), login.merge(storage)) }
          .to raise_error(RuntimeError, /OBJECT_STORAGE_BUCKET is set but OBJECT_STORAGE_REGION is unset/)
      end

      it "raises when the bucket's key is missing from the credentials" do
        expect { described_class.check!(ready.merge(backups), login) }
          .to raise_error(RuntimeError, /object_storage\.access_key_id and object_storage\.secret_access_key are unset/)
      end

      it "accepts a mounted folder in place of a bucket" do
        expect { described_class.check!(ready.merge("BACKUP_PATH" => "/backups"), login) }
          .not_to raise_error
      end

      it "refuses a folder and a bucket at once, since a backup goes to one place" do
        expect { described_class.check!(ready.merge(backups, "BACKUP_PATH" => "/backups"), login.merge(storage)) }
          .to raise_error(RuntimeError, /BACKUP_PATH and OBJECT_STORAGE_BUCKET are both set/)
      end

      it "names the fix, the doc and the opt-out in the message" do
        described_class.check!(ready.merge(backups), login)
        raise "expected check! to raise"
      rescue RuntimeError => e
        expect(e.message).to include("credentials:edit --environment production")
        expect(e.message).to include("/docs/developer/deployment")
        expect(e.message).to include("git rm config/initializers/required_production_config.rb")
        expect(e.message).to include("BACKUP_PATH")
      end
    end
  end

  describe "boot wiring" do
    let(:source) { Rails.root.join("config/initializers/required_production_config.rb").read }

    it "fires only for real production boots, sparing build-time asset precompile" do
      wiring = source.lines.last
      expect(wiring).to include("Rails.env.production?")
      expect(wiring).to include('ENV["SECRET_KEY_BASE_DUMMY"]')
    end
  end
end

# Host authorization is production-only config, so (like the tenancy
# initializer spec) we assert the source of truth rather than booting a
# production process per example.
RSpec.describe "config/environments/production.rb host authorization" do
  let(:source) { Rails.root.join("config/environments/production.rb").read }

  it "derives config.hosts from RAILS_HOST (DNS-rebinding protection on by default)" do
    line = source.lines.find { |l| l.strip.start_with?("config.hosts") }
    expect(line).to include('ENV["RAILS_HOST"]')
  end

  it "excludes /up from host authorization so the Kamal healthcheck cannot be blocked" do
    line = source.lines.find { |l| l.strip.start_with?("config.host_authorization") }
    expect(line).to include('request.path == "/up"')
  end

  it "decrypts the credentials a deploy names in RAILS_CREDENTIALS_ENV, before anything reads them" do
    wiring = source.index("config.credentials.merge!(DeployCredentials.paths(ENV))")
    expect(wiring).not_to be_nil
    expect(wiring).to be < source.index("MailDelivery.smtp_settings")
  end

  it "takes its SMTP settings from MailDelivery, so a provider is a change of secrets" do
    expect(source).to include("config.action_mailer.smtp_settings = MailDelivery.smtp_settings(ENV)")
  end

  it "lets a failed delivery fail its job instead of vanishing" do
    expect(source).to include("config.action_mailer.raise_delivery_errors = true")
  end
end
