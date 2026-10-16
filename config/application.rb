require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ModelrailsBase
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.2

    config.yjit = true

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # rubocop: house cops, loaded by RuboCop itself (.rubocop.yml require:), never by the app.
    config.autoload_lib(ignore: %w[assets tasks rubocop])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Pin the locale universe. Without this, `I18n.available_locales` is derived
    # from the load path — and `faker` (a development/test gem shipping ~350
    # locale files) makes that ~60 entries in test versus [:en] in production.
    # Since `I18n.translate` calls `enforce_available_locales!` before reaching
    # the backend, a user-supplied locale then resolves under test and raises
    # `I18n::InvalidLocale` in production. Pinning makes every environment agree.
    #
    # FORK SEAM: adding a language means adding it here as well as adding the
    # locale files. This is the one list that decides what the app will accept.
    config.i18n.available_locales = [ :en ]
    config.i18n.default_locale = :en

    # Don't generate system test files.
    config.generators.system_tests = nil

    config.x.signup.mode = ENV.fetch("SIGNUP_MODE", "invite_only").to_sym

    # Off by default: the template avoids storing passwords. See /docs/developer/security (Password sign-in).
    config.x.authentication.passwords = ENV.fetch("AUTH_PASSWORDS", "disabled").to_sym

    # Instance ceiling on per-workspace Workspace#join_policy. Defaults to
    # [:invite] (preserves Solo-default). Operators opt in to :open_link by
    # setting SIGNUP_PERMITTED_JOIN_STRATEGIES=invite,open_link.
    # See app/docs/developer/presets.md and docs/reshape-2-per-workspace-join-policy-spec.md.
    config.x.signup.permitted_join_strategies =
      ENV.fetch("SIGNUP_PERMITTED_JOIN_STRATEGIES", "invite").split(",").map { |s| s.strip.to_sym }

    # Tenancy preset configuration. See app/docs/developer/presets.md.
    config.x.tenancy.onboarding          = ENV.fetch("WORKSPACE_ON_SIGNUP", "personal").to_sym
    config.x.tenancy.workspace_creation  = ENV.fetch("TENANCY_WORKSPACE_CREATION", "enabled").to_sym
    config.x.tenancy.shared_workspace_slug = ENV["TENANCY_SHARED_WORKSPACE_SLUG"]
  end
end
