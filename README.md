# ModelRails

A multi-tenant SaaS starter kit built on Rails 8.1.

## Tech Stack

- **Framework:** Rails 8.1, Ruby 4.0.9
- **Database:** SQLite (Solid Queue/Cache/Cable in-process)
- **Frontend:** TailwindCSS 4, Turbo, Stimulus
- **Assets:** Propshaft, Importmaps
- **Auth:** Rails 8 authentication generator; passwordless-first magic links, passkeys (WebAuthn), OmniAuth (Google, GitHub), Pundit
- **Real-Time:** Turbo Stream broadcasts (morph-based refresh)
- **Content:** Action Text with [Lexxy](https://github.com/basecamp/lexxy) (Lexical-based rich text editor)
- **Docs:** Markdowndocs engine at `/docs` (deployment, background jobs, getting started, architecture, security, …)
- **Testing:** RSpec, FactoryBot, Capybara, Cuprite (pure-Ruby CDP), axe-core (WCAG 2.2 AAA), Bullet (N+1 detection)
- **Security:** Rate limiting, security headers, CSP, Pwned password check
- **Deployment:** Kamal → GitHub Container Registry; the production image build is checked on pull requests that change a build input, on every push to `main`, and by the pre-push hook
- **Version Management:** [mise](https://mise.jdx.dev/) (see `.tool-versions`; `Gemfile` reads from it so Bundler enforces the Ruby version everywhere)
- **Dev Container:** Optional VS Code Dev Container ships with `ruby:4.0.9-slim` base (matches production), `docker-outside-of-docker` for in-container `kamal deploy`, named bundle cache volume

## Setup

### Prerequisites

- [mise](https://mise.jdx.dev/) (or asdf) for runtime version management
- Chrome or Chromium installed (Cuprite/Ferrum auto-detects an installed browser for system tests — it does not download one)

### Getting started

```bash
# Install the Ruby version from .tool-versions
mise install

# Install dependencies, prepare database, start server
bin/setup
```

Or step by step:

```bash
bundle install
bin/rails db:prepare
bin/dev
```

### Running tests

```bash
bin/parallel-rspec   # full suite across all cores + integrity gates (what CI runs)
bundle exec rspec    # single-process run (focused files, debugging)
```

With documentation output:

```bash
bundle exec rspec --format documentation
```

Coverage report is generated at `coverage/index.html`.

### OAuth configuration

Google and GitHub OAuth require credentials. Add them via per-environment Rails
credentials (the template ships none; the first run generates the file and key):

```bash
bin/rails credentials:edit --environment development
```

Add the following structure:

```yaml
oauth:
  google:
    client_id: your_google_client_id
    client_secret: your_google_client_secret
  github:
    client_id: your_github_client_id
    client_secret: your_github_client_secret
```

OAuth is optional — email/password sign-up works without it.

## Forking this template

This repo is an upstream template: clone it with full history, build your product
in fork-owned files, and merge upstream improvements back in periodically.

```bash
git clone git@github.com:dschmura/modelrails_base.git myapp
cd myapp
bin/fork      # remote surgery + identity rename + tenancy preset, then bin/setup
```

`bin/fork` runs once per fork, before `bin/setup`, and prints every git command
it runs. Teammates cloning your app afterwards run only `bin/setup`. The by-hand
equivalent is in the forking guide.

The complete guide — identity-rename checklist, secrets bootstrap, the fork-owned
file contract, and the upstream-update workflow — lives in
[app/docs/developer/forking.md](app/docs/developer/forking.md), rendered at `/docs/developer/forking` in the
running app. Your fork inherits it.

## What's included

A multi-tenant SaaS kit, not an auth starter: workspaces with roles and
invitations, projects with per-project collaboration, a polymorphic resource
registry with rich-text documents, device/session management, and a
workspace-visible activity trail — on top of the authentication below.

### Workspaces & tenancy
- Multi-tenant workspaces with four system roles (Owner, Admin, Member, Viewer), role permissions, member management, invitations (email + magic-link), open join links, and workspace branding (logo, primary color)
- Tenancy presets (personal / shared / none) selected by env, with onboarding to match
- Suspension/archive/soft-delete lifecycle with guarded transitions
- An instance-operator area (`/operations`) above the workspaces: create and lock workspaces, look users up, suspend and reinstate accounts, grant other operators — 404 to everyone else, reauthenticated on every request, every action in the audit trail

### Projects & resources
- Projects as collaboration spaces with creator/editor/viewer memberships, pinning, capacity limits, and per-project tool toggles
- Polymorphic resource registry (documents via Action Text + Lexxy) with client-visible sharing and an external client area

### Sessions & activity
- Device/session management (list, revoke others, revoke on credential change), passkey (WebAuthn) sign-in and management
- Best-effort activity log with workspace-visible feed and 12-month retention sweep

### Authentication
- Smart sign-in: single email field routes users to the right auth method
  - Existing user with password → password form (with "send magic link instead" option)
  - Existing passwordless user → magic link sent automatically
  - Unknown email → registration magic link sent
- Magic link sign-in with 15-minute token expiry and one-time use
- Passwordless registration via magic link (name-only form, no password required)
- Email/password sign-up with 12-character minimum and Pwned password breach detection
- Account locking after 5 failed attempts (1-hour auto-unlock)
- Password reset using Rails 8.1 signed tokens (15-minute expiry)
- Email verification with 24-hour token expiry
- Turbo Frame inline transitions (check-email confirmation replaces form in-place)

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by email for new OAuth signups (matches verified existing users)
- Signed-in users can link additional providers; if the OAuth-returned email matches the user's primary email, the link auto-verifies, otherwise a verification email is sent to the OAuth address and the link stays pending until clicked
- Pending OAuth authentications cannot sign in. Users can resend the confirmation email (rate-limited per user) or cancel the pending link from connected accounts
- 24-hour token expiry on verification links; cross-user collision blocked; per-user rate limit on resend
- OAuth-only users can add email/password sign-in

### Account management
- Profile editing (name, email)
- Avatar upload (Active Storage) with Gravatar fallback
- Connected accounts view with last-verified-method protection (can't remove the only verified sign-in method; pending auths can always be cancelled)
- Theme preferences (light, dark, system) with Stimulus controller and Turbo Stream updates

### UI
- All text via I18n locale files (no hardcoded strings)
- WCAG 2.2 AAA, enforced by an automated axe-core gate in both themes (scope honestly documented in [/docs/developer/accessibility](https://github.com/dschmura/modelrails_base/blob/main/app/docs/developer/accessibility.md))
- Skip-to-content link, semantic HTML landmarks
- 44px minimum touch targets on interactive elements
- Dark mode support throughout
- Accessible forms with labels, ARIA attributes, and focus rings
- Design system primitives via the vendored [modelrails_ui](https://github.com/dschmura/modelrails_ui) component library (`UI::*` ViewComponents, OKLCH semantic tokens); Lookbook previews at `/lookbook` in development

### Static pages
- Home, About, Privacy, Contact

## Development

### Project structure

```
app/
  controllers/
    settings/                         # Profile, avatar, password, passkeys, theme, connected accounts
    concerns/
      authenticatable.rb              # Rails 8 auth concern
      signupable.rb                   # One transaction for a new user and their pending claims
    sessions/
      lookups_controller.rb           # Email-first step: sends a sign-in or registration link
    sessions_controller.rb            # Sign-in page and password sign-in
    magic_links_controller.rb         # Request a magic link
    magic_link_callbacks_controller.rb  # Open a magic link; registration form for a new email
    magic_link_callbacks/
      sessions_controller.rb          # Spend the token and start the session (existing user)
    password_resets_controller.rb
    email_verifications_controller.rb
    omniauth_callbacks_controller.rb
    pages_controller.rb
  models/
    user.rb               # Core user; the optional password lives in user/password.rb
    session.rb            # DB-backed sessions
    magic_link_token.rb   # Secure tokens for passwordless sign-in and registration
    authentication.rb     # Multi-provider identity (email, Google, GitHub)
    user_preferences.rb   # Theme, locale, timezone
  mailers/
    authentication_mailer.rb  # Verification + password reset emails
    magic_link_mailer.rb      # Sign-in and registration magic link emails
```

### Test suite

Tests are organized by type:

- `spec/models/` — Model validations, associations, business logic
- `spec/requests/` — Controller/integration tests
- `spec/system/` — Browser tests with Cuprite (headless Chromium via CDP; no Node)
- `spec/mailers/` — Mailer content and delivery tests
