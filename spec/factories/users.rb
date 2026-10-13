FactoryBot.define do
  factory :user do
    # Sequence-prefixed so uniqueness is impossible to violate by construction,
    # not merely improbable — the authentications default below mirrors this
    # address into the GLOBAL (provider, uid) unique index on every create,
    # where a Faker collision would surface as RecordInvalid from inside the
    # factory callback, on a row the failing spec never mentions (#856).
    sequence(:email_address) { |n| "user-#{n}-#{Faker::Internet.email}" }
    password { "SecureP@ssw0rd123!" }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    # Default: already-onboarded user — the passkey enrollment banner will not
    # appear, keeping it out of the system specs that don't test it. (The banner
    # is non-blocking; this just avoids incidental noise.)
    passkey_prompt_seen_at { Time.current }

    # Every production signup leaves at least one authentication: magic-link
    # registration creates the email row verified (the mailbox round trip is
    # the proof), password-set creates it pending on purpose, and OAuth signup
    # creates a verified provider row with no email row at all. A user with
    # ZERO authentications is the state production cannot reach. The default
    # here is the magic-link shape — the most common one in a passwordless-
    # first template — and the exceptional states are named traits.
    #
    # Carried on a transient read by ONE callback, so combining traits resolves
    # by FactoryBot's documented last-trait-wins override precedence instead of
    # by which trait-local callback happened to run first — a second callback's
    # find_or_create_by! would have found the first's row and silently kept its
    # verified_at (#850).
    transient do
      email_authentication { :verified }
    end

    after(:create) do |user, evaluator|
      case evaluator.email_authentication
      when :none then next
      when :verified, :pending
        user.authentications.create!(
          provider: "email",
          verified_at: (Time.current if evaluator.email_authentication == :verified)
        )
      else
        raise ArgumentError, "email_authentication must be :verified, :pending or :none, "                              "got #{evaluator.email_authentication.inspect}"
      end
    end

    trait :passkey_prompt_pending do
      passkey_prompt_seen_at { nil }
    end

    trait :suspended do
      suspended_at { Time.current }
    end

    # Magic-link / OAuth-only account — the common case in a passwordless-first
    # app, and the reason re-auth can't assume a password.
    trait :passwordless do
      password { nil }
      password_digest { nil }
    end

    # Has an address on file but has not proven it — what password-set alone
    # produces. Cannot invite.
    trait :unverified_email do
      email_authentication { :pending }
    end

    # The OAuth-signup shape: one verified provider row and NO email row —
    # what a verified Google/GitHub signup actually creates (see
    # app/lib/oauth_link.rb). The second reachable "signed-up user" in
    # production, and the honest fixture for any example whose subject is a
    # user with no email authentication. The uid derives from the row's own
    # user, so it is unique by construction. Combining with the email traits
    # is additive: this row is created regardless, and the email transient
    # still resolves last-wins.
    trait :oauth_only do
      email_authentication { :none }

      after(:create) do |user|
        user.authentications.create!(
          provider: "google",
          uid: "google-uid-#{user.id}",
          email: user.email_address,
          verified_at: Time.current
        )
      end
    end

    # No authentications row of any provider. Production cannot reach this;
    # use it when the example constructs its own authentication rows (the
    # default's email row would collide — provider is unique per user) or
    # asserts their absence. If you are about to hand-build a VERIFIED email
    # row on top of this, you wanted the plain default.
    trait :no_authentications do
      email_authentication { :none }
    end

    trait :with_avatar do
      after(:create) do |user|
        fixture = Rails.root.join("spec/fixtures/files/avatar.png")
        user.avatar.attach(io: File.open(fixture), filename: "avatar.png", content_type: "image/png")
        user.avatar_original.attach(io: File.open(fixture), filename: "original.png", content_type: "image/png")
        user.update!(avatar_source: "upload")
      end
    end

    trait :with_gravatar do
      has_gravatar { true }
    end

    # Persists the user with zero workspaces and no personal_workspace_id by
    # saving under the :none tenancy posture — the real production branch of
    # onboard_workspace, not a stubbed-out callback. Scoped to THIS create
    # (config restored in ensure), so other factory calls in the same example
    # still onboard normally. Used by zero-workspace crash-safety specs.
    trait :with_zero_workspaces do
      to_create do |user|
        # [] reads and writes past a stubbed #onboarding reader, so the restore never writes a stub's value back.
        tenancy = Rails.configuration.x.tenancy
        if tenancy.onboarding != tenancy[:onboarding]
          raise "with_zero_workspaces cannot run while tenancy onboarding is stubbed: create the user before the stub"
        end

        original = tenancy[:onboarding]
        tenancy[:onboarding] = :none
        begin
          user.save!
        ensure
          tenancy[:onboarding] = original
        end
      end
    end
  end
end
