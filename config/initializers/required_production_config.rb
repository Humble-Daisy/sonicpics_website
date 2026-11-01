# Refuses to boot production with configuration that comes up green and broken:
# a placeholder RAILS_HOST passes /up while every mailer link points at a domain
# this app does not control; missing encryption keys pass /up while the first
# user read raises. Deterministic checks only — a previously-healthy config
# must never fail a restart. See /docs/developer/deployment (Production
# preflight).
module RequiredProductionConfig
  # example.com is IANA-reserved (RFC 2606); `.example` is the TLD bin/fork
  # substitutes into placeholders. Neither can ever be a real deployment host.
  PLACEHOLDER_HOST = /\A(.+\.)?example(\.com)?\z/
  # Where Rails mails by default; nothing listens there on a deployed host.
  LOOPBACK = /\A(localhost|127\.0\.0\.1)\z/

  # The three values `bin/rails db:encryption:init` generates. Credentials are
  # the template's home for them; the config path is the environment-variable
  # alternative the Rails guide documents.
  ENCRYPTION_KEYS = %i[primary_key deterministic_key key_derivation_salt].freeze

  def self.check!(env = ENV, credentials = Rails.application.credentials,
                  encryption = Rails.application.config.active_record.encryption, logger: Rails.logger)
    check_host!(env)
    check_mail!(env, credentials)
    check_encryption_keys!(credentials, encryption)
    check_backups!(env, credentials, logger)
  end

  def self.check_backups!(env, credentials, logger)
    if env.values_at("BACKUP_PATH", "OBJECT_STORAGE_BUCKET").all? { |value| value.to_s.strip.empty? }
      return logger.warn("Backups are off: nothing copies the database or uploaded files anywhere. " \
        "Set BACKUP_PATH (a folder) or OBJECT_STORAGE_BUCKET (a bucket); /docs/developer/deployment (Back up the database section).")
    end
    problem = backups_problem(env, credentials) or return

    raise <<~MSG
      Production preflight failed: #{problem}.

      A half-configured backup destination boots, /up reports healthy, and every
      backup fails.

      Fix, either way under env.clear in config/deploy.yml (Kamal), or the environment:
        - A folder, such as a NAS or a second drive passed in as a volume: BACKUP_PATH,
          with OBJECT_STORAGE_BUCKET removed
        - Or finish the bucket: OBJECT_STORAGE_REGION (and OBJECT_STORAGE_ENDPOINT for
          anything but AWS), plus object_storage.access_key_id and
          object_storage.secret_access_key in bin/rails credentials:edit --environment production

      Details: /docs/developer/deployment (Back up the database section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.backups_problem(env, credentials)
    path, bucket = env.values_at("BACKUP_PATH", "OBJECT_STORAGE_BUCKET").map { |value| value.to_s.strip }
    return "BACKUP_PATH and OBJECT_STORAGE_BUCKET are both set; a backup goes to one of them" if path.present? && bucket.present?
    return if path.present?
    return "OBJECT_STORAGE_BUCKET is set but OBJECT_STORAGE_REGION is unset" if env["OBJECT_STORAGE_REGION"].to_s.strip.empty?

    blank = %i[access_key_id secret_access_key].select { |key| credentials.dig(:object_storage, key).to_s.strip.empty? }.map { |key| "object_storage.#{key}" }
    "#{blank.to_sentence} #{blank.one? ? "is" : "are"} unset in credentials" if blank.any?
  end
  private_class_method :backups_problem

  def self.check_mail!(env, credentials)
    problem = mail_problem(env, credentials) or return

    raise <<~MSG
      Production preflight failed: #{problem}.

      Sign-in is an email. Without a mail server it can log in to, the app boots,
      /up reports healthy, and every magic link, invitation and reset is a failed job.

      Fix: point SMTP_ADDRESS at your provider and put its login in credentials
        - SMTP_ADDRESS: under env.clear in config/deploy.yml (Kamal), or the environment
        - smtp.user_name and smtp.password: bin/rails credentials:edit --environment production
          (staging: --environment staging), then redeploy

      Details: /docs/developer/deployment (Configure outbound mail section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.mail_problem(env, credentials)
    address = env["SMTP_ADDRESS"].to_s.strip
    return "SMTP_ADDRESS is unset" if address.empty?
    return "SMTP_ADDRESS is #{address.inspect}" if LOOPBACK.match?(address) || PLACEHOLDER_HOST.match?(address)

    blank = %i[user_name password].select { |key| credentials.dig(:smtp, key).to_s.strip.empty? }.map { |key| "smtp.#{key}" }
    "#{blank.to_sentence} #{blank.one? ? "is" : "are"} unset in credentials" if blank.any?
  end
  private_class_method :mail_problem

  def self.check_host!(env)
    host = env["RAILS_HOST"].to_s.strip
    return unless host.empty? || PLACEHOLDER_HOST.match?(host)

    raise <<~MSG
      Production preflight failed: RAILS_HOST is #{host.empty? ? "unset" : host.inspect}.

      Every mailer link (magic links, password resets, invitations) is built from
      RAILS_HOST, and DNS-rebinding protection (config.hosts) is derived from it.
      With a placeholder value the app boots, /up reports healthy, and nobody can
      sign in — the failure is invisible from the outside.

      Fix: set RAILS_HOST to this deployment's public hostname (e.g. app.yourdomain.com)
        - Kamal: add RAILS_HOST under env.clear in config/deploy.yml, then redeploy
        - Anything else: set the RAILS_HOST environment variable

      Details: /docs/developer/deployment (Production preflight section).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end

  def self.check_encryption_keys!(credentials, encryption)
    missing = ENCRYPTION_KEYS.reject do |key|
      encryption[key].present? || credentials.dig(:active_record_encryption, key).present?
    end
    return if missing.empty?

    raise <<~MSG
      Production preflight failed: Active Record encryption keys are missing
      (#{missing.map { |key| "active_record_encryption.#{key}" }.join(", ")}).

      Personal data — email addresses, names, company names — is encrypted at
      rest. Without the keys the app boots and /up reports healthy, and the first
      read or write of a user raises.

      Fix: run `bin/rails db:encryption:init` and paste its block into
        bin/rails credentials:edit --environment production

      Details: /docs/developer/forking (Bootstrap secrets and configuration).
      Opting out for good: git rm config/initializers/required_production_config.rb
    MSG
  end
end

# SECRET_KEY_BASE_DUMMY marks build-time boots (the Dockerfile's
# assets:precompile), where deployment ENV is legitimately absent.
RequiredProductionConfig.check! if Rails.env.production? && !ENV["SECRET_KEY_BASE_DUMMY"]
