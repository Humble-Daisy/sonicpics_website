---
title: Email Flows
description: All transactional emails, their triggers, token expiry windows, and customization
keywords: email mailer authentication invitation magic link verification token expiry smtp
code:
  signup:
    - app/controllers/sessions/lookups_controller.rb
    - app/models/magic_link_token.rb
    - app/mailers/magic_link_mailer.rb
    - app/views/magic_link_mailer/
    - app/controllers/magic_link_callbacks_controller.rb
    - app/views/magic_link_callbacks/
---

# Email Flows

ModelRails sends transactional emails for authentication, invitations, and account management. All emails are delivered asynchronously via `deliver_later` (Solid Queue) and are fully internationalized.

## Mailers

| Mailer | Purpose |
|--------|---------|
| `AuthenticationMailer` | Email verification, email change |
| `InvitationMailer` | Workspace and project invitations |
| `MagicLinkMailer` | Passwordless sign-in and registration links |

## Email Reference

### Authentication Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Verification | New account registration | User's email | 24 hours |
| Email change verification | Email change initiated | New email address | 24 hours |
| Email change notification | Email change initiated | Current email address | N/A (informational) |

### Invitation Emails

| Email | Trigger | Mailer action | Recipient | Expiry |
| ----- | ------- | ------------- | --------- | ------ |
| Workspace invitation | Admin invites a member by email | `InvitationMailer.with(invitation:).invite` | Invitee's email | 7 days |
| Project invitation | Project member invites a collaborator | `InvitationMailer.with(invitation:).invite` | Invitee's email | 7 days |
| Client invitation | Project member invites an external client | `InvitationMailer.with(invitation:).invite_client` | Client's email | 7 days |

`invite_client` is a client-flavoured variant: the subject references the project name (not the workspace). It carries the same decline link as the other two, so a client invitee can decline — and block that sender — from the email. See [Clientside](/docs/user/clientside) for the client area this invitation leads to.

### Magic Link Emails

| Email | Trigger | Recipient | Expiry |
|-------|---------|-----------|--------|
| Sign-in link | Existing user requests passwordless sign-in | User's email | 15 minutes |
| Registration link | New email requests account creation | Entered email | 15 minutes |

## Token Security

All tokens are generated via `SecureRandom.urlsafe_base64(32)` (256 bits of entropy). Each token type has a fixed expiry window that cannot be extended — if a token expires, the user must request a new one.

Tokens are single-use: accepting an invitation, verifying an email, or resetting a password invalidates the token immediately.

## User Flows

### New User Registration (magic-link / passwordless-first)

1. User enters their email on the sign-in/sign-up page (`sessions#new`) and submits.
2. `Sessions::LookupsController#create` issues a `MagicLinkToken` and sends `MagicLinkMailer.registration_link` (new email) or `MagicLinkMailer.sign_in_link` (existing account).
3. User clicks the link (GET) → `MagicLinkCallbacksController#show` checks for an existing account. The GET never consumes the token or starts a session (a mail scanner or prefetcher can't burn the link):
   - Existing user: renders a "Sign in as x@y?" confirmation page; the button POSTs to the nested session (`POST /magic_link_callback/:token/session`), which consumes the token and starts the session.
   - New user: renders `magic_link_callbacks/new_registration` (name fields) for first-time signup.
4. New user submits their name → `MagicLinkCallbacksController#create` creates the User and a **verified** `Authentication` (email ownership proved by the link). No separate verification email is sent.
5. User is redirected to `after_authentication_url` (onboarding or home).
6. If the user is on the `:none` preset and has not yet completed onboarding, the `RequiresOnboarding` guard fires and redirects them into the onboarding wizard.

Verification can be resent from the "check your email" screen or via the banner if the original email was lost.

### Passwordless Sign-In (Magic Links)

1. User enters their email on the sign-in page.
2. If the email exists: `MagicLinkMailer.sign_in_link` sent (15-minute expiry).
3. If the email is new: `MagicLinkMailer.registration_link` sent instead.
4. User clicks link (GET) → confirmation page ("Sign in as x@y?") whose button POSTs to sign in (existing), or the registration form (new). The GET never signs anyone in.
5. The `MagicLinkCallbacksController` handles token validation and routing; the token is consumed only on the POST.

### Forgot password / account recovery

There is no password-reset email. "Forgot password?" issues a **magic link** (a
`MagicLinkToken` carrying a `set_password` intent); clicking it signs the user in
and lands them on the change-password form. Magic link is the single
email-recovery primitive — see [Passkeys](/docs/developer/passkeys) for the passwordless
sign-in options and [Application Flows](/docs/developer/application-flows) for the journey.

### Email Change

1. User enters a new email in the profile form. Requesting the change requires recent **re-authentication** (a 15-minute window), not a password — so passwordless accounts can change their email too.
2. `User::EmailChange#initiate!(new_email)` generates a `pending_email_token`.
3. Verification sent to new email, notification sent to old email.
4. User clicks verification link → `User::EmailChange#confirm!` atomically swaps the address.
5. All linked OAuth authentication UIDs are updated to the new email.

### Invitation Acceptance

1. Admin creates invitation → `InvitationMailer.with(invitation:).invite` sent (workspace member or project collaborator). For external client invitations, `InvitationMailer.with(invitation:).invite_client` is sent instead — it uses a client-flavoured subject and the same decline link.
2. Invitee clicks accept link.
3. If authenticated: accepted immediately, provided the account's email matches the invited address.
4. If not authenticated: the token is stashed, the invitee registers, and the invitation is claimed when they verify the invited email — not at signup.
5. All paths go through `Invitation.consume!`, which enforces the email match (emailless magic-link invitations excepted) before `Invitation#accept!` creates the workspace membership (and project membership if applicable).

## Configuration

### From Address

`ApplicationMailer` resolves the from address in this order:

1. `MAIL_FROM` in the environment
2. `Rails.application.credentials.dig(:mailer, :from)`
3. `noreply@` the mailer's default host (`RAILS_HOST`)

### SMTP Setup

Where mail goes comes from the environment (`SMTP_ADDRESS`, `SMTP_PORT`,
`SMTP_DOMAIN`); the login lives in the per-environment credentials:

```yaml
# bin/rails credentials:edit --environment production
smtp:
  user_name: your-user
  password: your-password
```

`lib/mail_delivery.rb` builds `config.action_mailer.smtp_settings` from both,
and production refuses to boot when either is missing. Provider recipes:
[Deployment](/docs/developer/deployment#4-configure-outbound-mail).

### Default URL Host

Set `config.action_mailer.default_url_options = { host: "yourapp.com" }` in each environment config. Email links use this to generate absolute URLs.

## Localization

All email subjects, greetings, body text, and button labels are defined in `config/locales/en/mailers.en.yml`. To translate emails, create locale files for your target language following the same key structure.
