---
title: Security
description: Security configuration, recommendations, and best practices for ModelRails
keywords: rate limiting account locking headers csp password oauth rack attack https clientside client access bearer token libvips heic content types direct upload email normalization punycode recipient throttle nonce form-action provider registry invitation block decline suppression deliverable ghost
---

# Security

## Built-In Protections

### Rate Limiting

Auth endpoints are rate-limited via Rails 8 `rate_limit` DSL:

| Endpoint | Limit | Window |
|----------|-------|--------|
| POST /session (sign in / email-first lookup) | 10 requests | 3 minutes |
| POST /passwords (reset) | 10 requests | 3 minutes |
| POST /magic_links (magic link) | 5 requests | 3 minutes |

### Per-Recipient Email Throttle

The rate limits above gate how fast any one sender can trigger email sends.
They do not stop a **distributed flood by recipient**: N distinct senders — a
coordinated attack, or one attacker with N accounts — each send once, each
stays under its own per-sender limit, and the victim's inbox still receives N
emails.

`EmailRecipientThrottle` (`app/lib/email_recipient_throttle.rb`) closes that
gap by gating on the **recipient** address: at most 3 sends per recipient per
kind per hour by default. The policy lives in the module, not at call sites —
tighten or loosen it there. The counter lives in `Rails.cache` (Solid Cache),
keyed by SHA-256 of the canonical email plus the kind; buckets are independent
per kind, so a flood of one email type doesn't suppress legitimate sends of
another. The throttle is **fail-open**: if the cache backend can't increment,
the email is sent — delivery matters more than the throttle in a degraded
state.

One per-kind override (SEC-9): `:magic_link` allows 5 sends per 15 minutes,
shared by all four magic-link send endpoints (lookup sign-in, registration,
resend, password reset). They all mint into one intent-blind supersede pool,
so they must share one budget or endpoint-hopping resets it. The window
matches the 15-minute token expiry: a throttled-out user is never stranded
longer than their newest link's lifetime, and an attacker gets at most the cap
in supersedes per window before the victim's link becomes untouchable.

### Verified addresses gate invitations

Sending an invitation requires a **proven** address: `User#can_invite?` is true only when the user holds an authentication whose `verified_at` is set. Every writer of that column got there by demonstrating control of the mailbox — clicking a signed link sent to it (`Authentication#verify!`, the magic-link callback) or a provider vouching for it (`OauthLink`, gated on `identity.email_verified?`) — or an operator vouching for an address they typed on the command line (`rails operators:grant`, the `:shared` seed's reasoning for its bootstrap owner; both create the row and never convert a pending one). One writer used to prove nothing: `Settings::PasswordsController#create` stamped `verified_at` on a freshly minted email authentication, and setting a password demonstrates control of the *session*, not of the address. That stamp is gone, which is what lets the predicate stay a simple existence check. The gate is only as strong as the weakest path that sets the column: if you add a `verified_at` writer, add it to the inventory in `spec/requests/can_invite_gate_spec.rb`.

### Invitation blocks (decline-and-block)

An invitee can stop an inviter's future invitations from reaching their
address. Since #951 the only way to do that is the **"Don't invite me again"
link in the invitation email itself**: it carries a signed, stateless
`generates_token_for :block_confirmation` token (payload `[status]`, so it dies
on accept, decline, block, or revoke; lifetime seven days, the invitation's
own) as a query parameter. The link opens a confirmation page
(`GET /invitation_block?token=`, no side effects) whose one button performs
`decline_and_block!` (`POST /invitation_block`) and renders the outcome in the
document. A refresh after that re-posts a spent token and lands on the home page
with "This link was already used, or the invitation has expired"; the
"already handled" page is reached only when a decline races the block. Nothing
reachable from a bearer invitation URL can block: the decline
page only points at the email link, and the former `POST /invitations/:token/block`
route is gone. Mailbox possession is the proof, the same proof accepting relies
on through email verification. An `InvitationBlock`
row means "invitations from inviter *I* to address *E* are not delivered".
Blocks are **email-keyed and account-independent**: they work for a decliner
with no account, survive the address later becoming a user, and do not follow
a user who changes their address. A block is policy state, not audit — it is
deleted with its inviter, and the operator door in
[Troubleshooting](/docs/developer/troubleshooting#operations) is the only way
to lift one.

When a delivery aimed at a blocked address is refused, the invitation is
stamped `suppressed_at` (a **ghost**) and, on the mailer sites, an
admin-visibility `invitation.delivery_suppressed` activity row records the
attempt. Suppression is delivery-side only: it never changes what the
invitation *is* or whether it can be accepted.
`Invitation#deliverable?` is `has_invitee? && !blocked_by_invitee?` — two named
checks so a `false` self-identifies (a magic-link invitation has nothing to
deliver, which is not a block and writes no row).

Four invariants hold the design together. Code that guards one cites it by
number, so the numbers live here:

- **I1 — Directional.** A block suppresses deliveries to the blocked-from address
  only, never to the inviter. Inviter-facing notifiers (declined, accepted,
  resent) never consult blocks, so decline-and-block still delivers exactly
  one decline notification.
- **I2 — Ghosts stay redeemable.** `acceptable?`, the `acceptable` scope, and
  `guard_acceptable!` never look at `suppressed_at`. A redemption error would
  hand the blocked inviter a detection oracle, and the accept page is fresh,
  informed consent — so a suppressed invitation can still be accepted by
  token (stored encrypted, never plaintext — see *Bearer Tokens in Request
  Logs*).
- **I3 — No oracle in the inviter's surfaces.** A ghost is an ordinary pending row
  in the members index; resend produces the same confirmation as a live
  invitation; and no activity row the inviter can read is written by
  suppression or by block creation. `bulk_invite!`'s counters stay symmetric
  with the unblocked case: re-inviting an address that already has a pending
  invitation counts `skipped` whether or not a block exists. The two paths get
  there differently — an unblocked duplicate is caught by the pending-address
  check, a blocked one collides with its own ghost in the index — but neither
  creates a record, so neither can be told apart by the count. The single-create
  paths (`Invitation.invite_client!`, `Workspaces::Projects::InvitationsController#create`)
  reach the same symmetry through `Invitation.already_invited?`, which refuses a
  re-invite when a *pending* row exists that is either unsuppressed (from any
  inviter) or this inviter's own — live *or* ghost. Both halves are scoped
  `pending`, not `acceptable`, to match the expiry-blind `pending_live` index:
  an expired pending row still holds the live slot, so a narrower pre-check
  would let a blocked re-invite succeed where an unblocked one is refused, once
  the first invitation ages out. Matched, both cases get the identical "already
  has a pending invitation" flash.
- **I4 — `suppressed_at` has exactly three writers, all callback-free.**
  Create-time on the bulk path (create attributes), retroactively at block
  creation (`update_column`), and the mailer guard (`update_column`) — never a
  callback-running `update!`. (`update_all` is the operator unblock's verb, not
  a writer's.) `Trackable` would otherwise publish the
  stamp to the workspace feed as an ordinary update, which is itself the
  oracle. A fourth writer, or a callback-running one, is a violation.

The honest claim is that a block is **not cheaply confirmable — not
unknowable**. A 100% non-response rate across repeated invitations is a
statistical tell, and ghosts expire with their invitations at 7 days.
Suppression buys the invitee deniability, not secrecy.

**Delivery-site roster.** Every place an invitation email can leave the app,
and the guard that stops it:

| # | Site | Guard |
| --- | --- | --- |
| 1 | `Invitation.bulk_invite!` (workspace invites, incl. onboarding) | `InvitationMailer` `before_action` + create-time stamp |
| 2 | `Invitation.invite_client!` | `InvitationMailer` `before_action` |
| 3 | `Workspaces::InvitationsController#resend` | `InvitationMailer` `before_action` |
| 4 | `Workspaces::Projects::InvitationsController#create` | `InvitationMailer` `before_action` |
| 5 | `WorkspaceInvitationExpiringSweepJob` (in-app + email dispatch) | `next unless invitation.deliverable?` — silent skip, no audit row |
| 6 | `NotificationMailer#workspace_invitation_expiring_soon` (the reminder's email leg) | `return unless @invitation.deliverable?` before `mail(...)` — silent skip |

Sites 1–4 share one guard, and so does every future `InvitationMailer` method
a fork adds — the `before_action` halts the action by setting an empty
`response_body`, not by `throw :abort`, which raises `UncaughtThrowError` in an
ActionMailer callback.
Site 6 exists because the reminder's preference gate runs at dispatch time: a
block landing between the sweep's dispatch and the mail's render is only
catchable at the final hop.

**Any new invitee-facing notifier must re-check `deliverable?` at its delivery
gate — the last hop it controls.** Adding a site to this table is part of
adding the notifier.

`invitation_declines#create` and `invitation_blocks#create` are both public,
unauthenticated endpoints and are rate-limited at 10 requests per 3 minutes
per IP.

### Password sign-in

**Off unless the instance opts in.** `config.x.authentication.passwords`
reads `AUTH_PASSWORDS` and defaults to `disabled`. Disabled means the routes
are not drawn: no password sign-in (`POST /session`), no password reset, no
`/settings/password`, no password factor at reauthentication, and no password
form at the lookup step. A leftover `set_password` link signs in and lands on
the home page. The template avoids storing passwords, so supporting them is a
fork's explicit choice: set `AUTH_PASSWORDS=enabled`.

When enabled, an observer must not learn whether an address has an account, holds a
password, or is locked. `PasswordSignIn` (`app/models/password_sign_in.rb`)
is the one place that decides a password attempt, and every failure it
returns is the same:

- **One response.** An unknown address, a wrong password, a blank password
  and a locked account all re-render the password step with status 422 and
  one generic message in the error summary, the address kept read-only.
  The password field is never refilled.
- **One duration.** A miss hashes the submitted password anyway, as Rails'
  `authenticate_by` does; so does an account without a password.
- **A blank password is not an attempt** and does not count toward the lock.
- **The lookup step answers every address alike:** the same "check your
  email" page, with the password form offered inline for everyone, so no
  URL carries the address. With signups closed an unknown address gets that
  page too, and no email.

### Account Locking

After 5 failed login attempts, accounts are locked for 1 hour. Auto-unlock occurs after the lockout period.
The page never says so: the holder gets `PasswordLockedNotifier` by email when
the lock starts. `register_failed_login!` decides under `with_lock`, so
concurrent failures count from the database rather than a stale load.

**Scope — password sign-in only, by design.** The failed-attempt counter and
the `locked?` gate live in the password path (`sessions#create`). Passkey and
magic-link sign-in do **not** check the lock: neither factor is brute-forceable
the way a password is (a passkey is a cryptographic assertion; a magic link
requires control of the inbox), so locking them out would punish exactly the
factors a locked-out user needs to get back in. Consequence to be aware of:
a locked account is locked out of *passwords*, not out of the account — the
owner can still sign in with a passkey or magic link. If your fork wants a
lock to mean "no sign-in at all", add the `locked?` check to
`magic_link_callbacks/sessions#create` and `Passkeys::AuthenticateCeremony` as well.

### Account suspension

An operator hold, separate from the failed-attempt lockout above: refused at
`start_new_session_for`, the one funnel every sign-in path uses (password,
magic link, passkey, OAuth), and again at session resumption. Sessions are
destroyed at suspend time; memberships, roles and project access are left
untouched, so reinstating a user restores them exactly. The hold refuses
sessions and the writes that ride on them: an OAuth callback for a held account
links nothing and spends no parked invitation (#1129). A magic-link token it
presents is still spent, because the token is consumed before the account is known.
`user.suspended`, `user.unsuspended` and `user.unlocked` are STRICT-tier
audit rows at `admin` visibility naming the operator as actor (none for a
rake run). The operations area refuses to suspend an operator; `rails
users:suspend` does not check, because it is the break-glass path.

Admin rake tasks:

```bash
rails 'users:unlock[email@example.com]'      # Unlock a locked account
rails 'users:verify[email@example.com]'      # Manually verify an email
rails 'users:suspend[email@example.com]'     # Suspend a user (sessions end, sign-in blocked; no operator guard)
rails 'users:unsuspend[email@example.com]'   # Unsuspend a user (restores sign-in)
rails 'workspaces:suspend[slug]'             # Lock a workspace (members blocked until unsuspended)
rails 'workspaces:unsuspend[slug]'           # Unlock a workspace
rails 'operators:grant[email@example.com]'   # Grant instance-operator access to a user
rails 'operators:revoke[email@example.com]'  # Revoke instance-operator access from a user (no last-operator guard)
rails operators:list                         # List instance operators
```

### Session Lifetime

Sessions expire — a signed-in session is not valid forever. `Session#expired?`
enforces two limits, both tunable in `config/initializers/sessions.rb`:

- **idle timeout** (default 30 days) — no activity for this long signs you out
- **absolute timeout** (default 90 days) — this long after sign-in regardless of activity

Expiry is enforced fail-closed in `Authenticatable#find_session_by_cookie`
(an expired session resolves to `nil`, so the sweeper is housekeeping, not a
security control), and the signed cookie carries a matching `expires:`.
`last_active_at` is refreshed through an in-memory throttle so the write stays
off the SQLite single-writer hot path. Changing or removing a password signs
out every *other* session; users can review and revoke devices at
`/settings/sessions`. `ExpiredSessionsSweepJob` deletes expired rows daily.

### Re-Authentication (Sensitive Changes)

Actions that add, remove, or change an authentication factor require a recent
proof of identity, so a borrowed session can't be turned into a takeover.
`Reauthenticatable#require_reauthentication!` gates: password change/removal,
passkey enrollment and deletion, email change, OAuth unlink, and every
action in the [instance-operations area](operations) (`/operations`). It
checks `Session#reauthenticated?` (a 15-minute window on
`reauthenticated_at`, set at sign-in and refreshed by the interstitial) and,
if stale, sends the user to `/settings/reauthentication`.

The interstitial offers only the factors the user has (`User#available_reauth_factors`):
password, a passkey (verified through `AuthenticateCeremony` **bound to the
current user** — another account's passkey is rejected), or a one-time
`ReauthenticationChallenge` code emailed and entered in-page (never a link, so
it can't be replayed into a sign-in). That code lasts 10 minutes
(`ReauthenticationChallenge::EXPIRY`); the interstitial derives its code-entry
state from whether a live challenge exists, so once one expires the page offers
to email a fresh one, and "Send a new code" supersedes the previous code at any
time. All of it is tunable in
`config/initializers/sessions.rb`; `reauth_enabled = false` makes the gate a
no-op — except passkey enrollment and the operations area, which stay gated
regardless: enrollment mints a durable, phishing-resistant credential and
revokes nothing, and the operations area suspends workspaces and mints
operatorships, so both are hard-wired
(`require_reauthentication!(force: true)`), and enrollment additionally
fires `PasskeyAddedNotifier`. Email changes are gated here rather than on a
password, so passwordless users can change their email. The operations gate
is also the only one that fires on GET requests, not just mutations — see
[Instance operations: How it stays safe](operations#how-it-stays-safe).

Sign-ins from an unrecognized browser/OS additionally trigger a security
notification (`SignInFromNewDeviceNotifier`). The alert is gated by
`new_device_notification` in the same initializer; device fingerprints are
recorded regardless, so turning the alert back on later keeps full history.

### Magic-Link Tokens

The bearer token is stored only as a SHA256 digest (`MagicLinkToken.token_digest`);
the plaintext lives solely in the emailed URL, so a leaked table can't be used
to sign in. 256 bits of entropy means a plain unsalted digest is sufficient —
contrast the 6-digit `ReauthenticationChallenge`, which needs a pepper + rate
limit. Clicking a magic link is a two-step GET→POST: the GET renders a
"Sign in as x@y?" confirmation and never consumes the token or starts a session,
so a mail scanner or prefetcher doing a bare GET can't burn the link; the POST
(the visible button) runs the atomic consume and signs in. Mirrors the join-link
confirmation flow. Email verification (both the first-email flow and
connected-account linking) follows the same GET-confirm / POST-verify shape,
and its token travels as a query parameter, not a path segment ([#950](https://github.com/dschmura/modelrails_base/issues/950)).

### Bearer Tokens in Request Logs

Four flows carry a bearer token as a URL path segment: the magic-link callback (`/magic_link_callback/:token`), invitation accept and decline (`/invitations/:token/…`; blocking moved behind a signed query-string link in the invitee's own email, #951), and workspace join links (`/workspaces/:slug/joins/:token`). Connected-account email verification moved its token to the query string (`/settings/connected_accounts/verify?token=…`, [#950](https://github.com/dschmura/modelrails_base/issues/950)); a legacy path-token alias (`/settings/connected_accounts/verify/:token`) stays live for one token lifetime (24 hours) past the 2026-09 deploy so in-flight emails still land, then it is removed. Rails writes a path segment into every `Started GET …` line verbatim: `config.filter_parameters` reaches query strings and form fields, and `Rails::Rack::Logger` logs `request.filtered_path`, which filters the query string and passes path segments through. (Active Storage's direct-upload route carries a five-minute signed token the same way.)

None of these five tokens is plaintext at rest. Magic-link and workspace-join-link tokens are stored only as SHA-256 digests (see *Magic-Link Tokens*); connected-account email verification is Rails' stateless `generates_token_for` and stores nothing at all. Invitation tokens (`invitations.token`) and the parked invitation token from an unverified-email OAuth signup (`authentications.pending_invitation_token`) are deterministically encrypted rather than digested, because the expiring-soon reminder and the notification mailer rebuild the accept URL from the token days after creation — a digest, being one-way, cannot be turned back into a link (#953). What this section accepts is a token's momentary appearance in a request-log line, never its form at rest.

**This is an accepted, recorded exposure, not an oversight** ([#916](https://github.com/dschmura/modelrails_base/issues/916), panel decision 2026-09-03). Redacting the Rails line would not change what is on the host: kamal-proxy writes its own JSON access log with the request `path` and the raw `query` for every request, so the same token lands on the same disk either way, and a token moved into the query string is logged there too. What bounds the exposure is topology, not redaction:

- Both logs are Docker `json-file` logs on the single deploy host, capped at 10 MB each by Kamal's defaults (`--log-opt max-size=10m` for the app container, `log_max_size` for the proxy) when `config/deploy.yml` sets nothing. Nothing is shipped off the host. The app-container log is replaced on each deploy and pruned with the last five containers; the proxy log is long-lived and rolls on size only, so it is the copy that holds a token longest.
- Reading either log needs `docker logs` over the deploy SSH key, which is root. Anyone who can read a token there can already read the database.
- Token lifetimes cap what a copy is worth. Magic-link tokens expire in 15 minutes, are single-use, and are superseded by requesting a new link. Presenting a spent one starts no session and consumes nothing: its owner, if already signed in, is told so (`authentication.already_signed_in`); anyone else gets the invalid answer. A superseded-but-unused link carries the same `consumed_at` as a redeemed one and is answered the same way — the distinction is [#1083](https://github.com/dschmura/modelrails_base/issues/1083). Invitation tokens expire in 7 days, are single-use, and accept refuses an email mismatch. Email-verification tokens expire in 24 hours. Workspace join links expire seven days after creation or rotation (`WorkspaceJoinLink::LIFETIME`), same as invitations, and an admin can also revoke one early ([#952](https://github.com/dschmura/modelrails_base/issues/952)).

**Rule for new work.** A secret goes in the query string or the request body, never in a path segment; `spec/code_smells/no_new_bearer_tokens_in_route_paths_spec.rb` holds the existing routes to a named allow-list and fails on a new one. Existing routes move only when they are touched for another reason (verification first, [#950](https://github.com/dschmura/modelrails_base/issues/950)), with both route shapes live for one token lifetime; join links move by forced rotation.

**Reopen this decision when any of these becomes true:** logs are shipped off the host (a log driver, a sidecar, a hosted aggregator); an error-reporting or APM gem is added, because Rails hands them `request.filtered_path` in the `process_action.action_controller` payload and the path token goes to a third party with no log configuration change; someone other than the deploy user gets host access; or a flow gains a long-lived or high-privilege path token (audit with `bin/rails routes | grep -E "/:[a-z_]*token"`). When a trigger fires, the Rails line and the proxy log must be addressed together.

### Security Headers

Rails 8.2's defaults (`load_defaults 8.2`) send these:

- `X-Frame-Options: SAMEORIGIN` — prevents clickjacking
- `X-Content-Type-Options: nosniff` — prevents MIME sniffing
- `X-Permitted-Cross-Domain-Policies: none`
- `Referrer-Policy: strict-origin-when-cross-origin`

`config/initializers/security_headers.rb` adds the one header Rails does not send: `Permissions-Policy`, which disables camera, microphone and geolocation by default. `X-XSS-Protection` is no longer sent, because every browser dropped the filter it controlled.

Content Security Policy lives in `content_security_policy.rb` (enforced in development, production, and test — see #499/#120 in `CHANGELOG.md` for why test enforcement matters); its decided trade-offs are documented in the next section.

### Cross-Site Request Forgery

Rails 8.2 verifies every write by the browser's `Sec-Fetch-Site` header rather than by an authenticity token (`load_defaults 8.2`, strategy `:header_only`). It first compares the request's `Origin` with the app's own URL. Then a request the header marks `same-origin` or `same-site` is allowed, and anything else is rejected with `ActionController::InvalidCrossOriginRequest`, a 422. A request with no header at all is allowed only over plain HTTP with SSL not forced, which in this app means development, and refused everywhere `force_ssl` is on. An authenticity token no longer rescues a request without the header.

Every browser that `allow_browser versions: :modern` admits sends the header, so a form or a `fetch` call needs no token. `csrf_meta_tags` stays in the layout, and the Stimulus controllers that still attach a token are harmless. No provider is listed in `protect_from_forgery trusted_origins:`, because the Google and GitHub callbacks are GET requests and the OmniAuth request phase is a same-origin POST. A fork whose provider posts its callback cross-site lists that provider's origin there.

`spec/requests/csrf_protection_spec.rb` is the one file that runs with forgery protection on. Codespaces turns off the Origin comparison only; see [Codespaces](codespaces).

### Content Security Policy

The CSP lives in `config/initializers/content_security_policy.rb`. Three of
its choices are decided trade-offs, not defaults waiting to be "fixed":

**`style-src` carries `unsafe-inline` (#444).** Tailwind 4 injects inline
`style` attributes and Turbo writes inline styles during morphs and
transitions, so a nonce/hash regime for styles breaks rendering in ways that
resurface with every framework update — a permanent breakage tax. The accepted
risk is narrow: style-only injection, with no script execution path
(`script-src` stays `'self'` plus a nonce). Revisit only if Tailwind and Turbo
ship nonce-compatible styling, not before.

**The script nonce is per-session, not per-request (#443).** The nonce
generator returns the session id, so one nonce is valid for a session's
lifetime. That lets Turbo cache and restore pages whose inline bootstrap still
validates — a per-request nonce invalidates every cached page's scripts on
restore. Cost accepted: a nonce leaked from one response is valid for the rest
of that session, a marginal loss since the session cookie it derives from is
the larger secret. Revisit only with a concrete injection vector that a
per-request nonce would have stopped. One subtlety: a visitor's *first*
request has no session yet, so the generator falls back to a random nonce —
emitting the invalid blank `'nonce-'` would be ignored by browsers, blocking
every inline script (the importmap bootstrap and `import "application"`) and
leaving Stimulus never booting for first-time visitors. Nonces apply to
`script-src` only.

**`form-action` is derived from the OAuth provider registry.** CSP evaluates
the entire redirect chain: the POST to `/auth/:provider` returns a 302 to the
provider's consent page, and browsers block that step unless the provider host
is in `form-action` — **silently**: no server error, nothing in the logs,
"clicking Sign in with SSO does nothing." The directive is built from
`config.x.oauth_providers` (#312) so a swapped provider can never be forgotten
here; `fetch` raises at boot on a registry entry without a `form_action_host`.
See [OAuth Security](#oauth-security) for the registry itself.

### Cookie classification

Every cookie the app sets is classified once, in
`config/initializers/biscuit.rb` (`Rails.application.config.cookie_classification`),
right beside Biscuit's own consent categories. The rule: a first-party cookie
that stores a choice the user just made through a control, carries no
identifier, and is read by no third party is `necessary` and needs no
consent banner gate; anything that profiles, measures, or is read by a third
party goes in its Biscuit category instead, and its write is gated on that
category's consent. `spec/initializers/cookie_classification_spec.rb` holds
the classification and this list together — a new cookie that lands in only
one of the two fails the suite.

| Cookie | Category | Reason |
|---|---|---|
| `session_id` | necessary | authentication session (the app's own signed cookie, `Authenticatable#start_new_session_for`) |
| `_<app_name>_session` (Rails' default session-store key, named for the application) | necessary | Rails' encrypted session cookie: CSRF token, flash messages, and short-lived flow state (pending join/invitation tokens, post-auth redirect target) |
| `biscuit_consent` | necessary | the consent record itself |
| `theme` | necessary | display choice made through a control; no identifier; first-party |
| `sidebar_collapsed` | necessary | layout choice made through a control; no identifier; first-party |

The next cookie goes in `config/initializers/biscuit.rb` and here; the spec
fails otherwise.

### Password Security

- 12-character minimum
- Pwned password check (Have I Been Pwned range API), run before `save` and outside the write transaction (see [Architecture § Concurrency](/docs/developer/architecture)). It is **fail-open**: a network failure allows the password rather than blocking registration on an external service.
- Account recovery issues a single-use `MagicLinkToken` (`set_password` intent, 15-minute expiry), not a stateless reset token

### Canonical Email Keys

`User#email_address` (and `pending_email`) are normalized through
`EmailNormalizer` (`app/lib/email_normalizer.rb`): Unicode-NFC-normalized,
stripped, downcased, with the **domain** punycode-encoded. Every email
comparison in the app — the invitation `EmailMismatch` guard, OAuth email
matching, email change — goes through `EmailNormalizer.equivalent?`, so
storage and lookup share a single canonical key.

Why NFC: visually identical strings can have different byte sequences
depending on Unicode form — "é" can be the single codepoint U+00E9 (NFC) or
"e" plus combining acute U+0301 (NFD). User input via web forms tends to be
NFC and OAuth providers usually return NFC, but rows imported from other
systems or copy-pasted from PDFs may be NFD. Without normalizing both sides,
the same mailbox can exist as two `User` rows (a duplicate account), or an
invitation or OAuth lookup can miss the account it should have matched.

Why punycode the domain: DNS only speaks ASCII, so an IDN like
`user@bücher.de` is encoded as `user@xn--bcher-kva.de` by mail servers. A user
might paste either form into a web form, but they are the same address —
normalizing to the ASCII (punycode) form gives both representations one
canonical key. The **local part** is deliberately untouched: SMTPUTF8
(RFC 6531) lets mailboxes accept Unicode local parts, and IDNA does not apply
there.

### Personal Data at Rest

Every column that holds something about a person is an Active Record
Encryption column — a database dump or backup carries ciphertext, not
addresses. Deterministic encryption (same plaintext, same bytes) is used only
where a finder or a unique index needs the column; everything else takes the
stronger non-deterministic cipher and cannot be searched or sorted in SQL —
which is why the members page filters and sorts in Ruby (`WorkspaceRoster`),
and why the operations activity ledger's search box resolves names the same
way (`ActivityLog::Search`) under a user-count cap rather than in SQL.

That Ruby pass decrypts every member row per search — on the order of 8 ms at
500 members and 100 ms at 5,000. Measure your own: load a workspace's
`WorkspaceRoster` in `bin/rails runner` and time `matching` at 1,000, 10,000
and 100,000 members. A blind index does not rescue this, and it is worth being
explicit about why, because it is the fix people reach for first: these
searches are substring matches, and a keyed digest answers equality only. The
day a workspace outgrows the Ruby pass, the choice is between narrowing the
match to a prefix or exact address and adding a plaintext search column — a
deliberate weakening of the posture this section describes. Either way it is a
product decision, not a migration.

| Column | Cipher | Why |
| ------ | ------ | --- |
| `users.email_address` | deterministic, downcased | sign-in lookup; unique index |
| `authentications.uid` | deterministic | `(provider, uid)` lookup and unique index; email-provider rows carry the user id, not the address (#903) |
| `invitations.email` | deterministic, downcased | one pending invitation per address per invitable |
| `magic_link_tokens.email` | deterministic, downcased | one unconsumed token per address |
| `users.pending_email`, `first_name`, `last_name` | non-deterministic | never looked up |
| `authentications.email`, `invitations.company_name`, `client_accesses.company_name` | non-deterministic | never looked up |

`workspaces.name` stays plaintext deliberately: the slug is the name,
parameterized, and sits in every URL. Two properties worth knowing: the
`deterministic_key` cannot be rotated (Rails raises on a key list), so it is
backed up with the credentials key; and the two
invitation-token columns are encrypted *differently* on purpose —
`invitations.token` is deterministic (its `find_by` lookup and unique index
need it) while `authentications.pending_invitation_token` is not (nothing
looks it up by value), so the same token does not encrypt to identical bytes
in both places. Keys are generated per fork — see
[Forking](/docs/developer/forking#bootstrap-secrets-and-configuration).
Rows written before a column was encrypted are unreadable by this release for
the personal-data columns from #902 — the template ships no conversion for
those. Invitation tokens are the exception: `invitations.token` and
`authentications.pending_invitation_token` ship one
(`db/migrate/20260903115906_encrypt_invitation_tokens_at_rest.rb`, #953),
re-runnable and reversible. For everything else, Rails' own coexistence path
(`support_unencrypted_data`, `extend_queries`, `record.encrypt`) is documented
in the Active Record Encryption guide under "Migrating Existing Data".

### OAuth Security

- OAuth email matching requires a verified email authentication on the existing account
- Unverified accounts are not linked — a new user is created instead

**Provider registry.** `config/initializers/0_oauth_provider_registry.rb` is
the single home for OAuth provider knowledge (#312). Three consumers derive
from it rather than repeating it: the CSP builds `form-action` from each
entry's `form_action_host` (see [Content Security Policy](#content-security-policy)
above), `config/initializers/omniauth.rb` declares strategies for the
registry's keys, and `app/helpers/oauth_helper.rb` renders sign-in buttons
from `name`/`icon`. Duplicated knowledge does not announce its drift; it just
waits — centralizing the registry means a swapped provider can't be updated in
one place and forgotten in another. Two mechanics worth knowing: the `0_`
filename prefix makes the initializer sort before its consumers (initializers
run in filename order), and the registry lives on `config.x` because app
constants are not referenceable at initializer time (Zeitwerk). To add or swap
a provider: add the entry here (`form_action_host` is the consent-screen
origin the browser is redirected to), declare the strategy in `omniauth.rb`,
and update the literal cross-check hash in
`spec/initializers/content_security_policy_spec.rb` — the spec fails loudly
until you do, which is the point: double-entry bookkeeping on a
security-relevant value.

### Activity Tracking

The `Trackable` concern logs workspace-domain model changes to `ActivityLog` on a **best-effort** guarantee — the write rescues rather than failing the operation it describes. Sensitive attributes are automatically stripped from metadata:

- `token`, `password_digest`
- `oauth_token`, `oauth_refresh_token`

**Account-security events are a separate, stricter tier.** Password set/change/removal, passkey enrollment/removal, sign-in from a new device, and instance-operator grant/revocation write rows named in `ActivityLog::SECURITY_ACTIONS`, through `ActivityLog.record_security_event!`. The credential events — including operator grants and revocations — are written **in the same transaction as the mutation they record, with no rescue** — a failed audit write fails the credential write. Sign-in detection stays best-effort, because the `Session` row is already the primary record of a sign-in.

These rows are retained on their own floor (`ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR`, 365 days) rather than the general 12-month window. Rows at `personal` visibility (the account events above) are readable by their owner on `/settings/sessions`; rows at `admin` visibility (operator grants and revocations, whose actor is the granter when there is one — a rake grant records none — rather than the subject) appear in the operations feed instead. Full per-event table, including what corroborates each row: [Notifications § Security event audit coverage](/docs/developer/notifications). The matching in-app notification carries no retention floor of its own — it is attention state on the user's clock. The `ActivityLog` row is the record.

### Image Processing (Active Storage + libvips)

Active Storage processes variants with libvips (`variant_processor = :vips`, the Rails 8.1 default). Since Rails 8.1.3.1 it calls `Vips.block_untrusted(true)` while booting, disabling the loaders and savers libvips flags as unsafe for untrusted input. That is what closes CVE-2026-66066, where a crafted upload could be used to read arbitrary files from the server — including the process environment, and therefore `secret_key_base`.

Two consequences to know about:

- **libvips 8.13+ and ruby-vips 2.2.1+ are required.** Below either, Active Storage raises at boot rather than run unsecured. The production image, the devcontainer and CI all satisfy this; check your own if you build a custom image.
- **BMP, ICO and PSD variants raise `Vips::Error`.** `config/initializers/active_storage.rb` subtracts exactly those three (`image/bmp`, `image/vnd.microsoft.icon`, `image/vnd.adobe.photoshop`) from `variable_content_types`, which makes `Blob#representable?` false, so the blob partial renders its file-chip branch instead. Without the subtraction they render an `<img>` whose variant fails when the browser fetches it — Action Text attachments carry no content-type allowlist and processing is lazy — and the image request falls back to the placeholder described below. The subtraction is exact by verification, not guesswork: on libvips 8.18.4 under `Vips.block_untrusted(true)`, every other entry in the default list (PNG, JPEG, GIF, WebP, TIFF, AVIF, HEIC, HEIF) still loads and transforms — nothing else may be removed there. A fork that needs one of the three should re-enable the specific libvips operation rather than living with the file chip.

**A variant that fails to process answers its image request instead of raising.** Processing is lazy, so it fails on the image request, not the page. `ActiveStorage::RepresentationFailures` answers a permanent failure (Hot Cell's `HotCell::PermanentFailure`, or `Vips::Error` in process) with a cacheable redirect to a neutral placeholder image, on the asset host when one is set. It answers a transient one (`HotCell::TransientFailure`: a cell restarting, full or unreachable) with a 503, `Cache-Control: no-store` and `Retry-After: 5`. Nothing caches the miss, so the next page view fetches the image again; a browser does not retry the `<img>` on its own. One misconfiguration still 500s on purpose: with `HOTCELL_GROUP` set to a group the app does not hold, the client's own `chown` raises `Errno::EPERM`, and the app's boot log names the fix ([Hot Cell](/docs/developer/hot-cell)).

The initializer governs what renders as a *variant*. What can be *uploaded* is gated per surface — avatar/logo attachments by model validations, rich-text direct uploads by `DirectUploadsController` (next section). Widen those, not the initializer.

Uploads backing user avatars, workspace logos and project logos are restricted by model validations to `ApplicationRecord::IMAGE_CONTENT_TYPES` (PNG, JPEG, GIF, WebP, HEIC, HEIF) with size caps. That list is deliberately **wider** than `ActiveStorage.web_image_content_types`, which is the set a browser renders directly: Rails converts a variant of anything outside that set to PNG automatically, so the constraint that matters is "can libvips process it safely", not "can a browser display it". HEIC/HEIF is the iPhone camera default — excluding it would bounce the single most common source of an avatar or logo upload for no security benefit: both types load and transform under `Vips.block_untrusted(true)` and remain in `variable_content_types`, and the production base image (Debian's libvips 8.16.1 in `ruby:slim`) ships `heifload` and `heifsave`. The list is one shared constant rather than a copy per model because a single list guards four attachments across two models — a copy per call site is how #496's drift happened.

### Rich-Text Direct Uploads (SEC-7)

Rich-text (Action Text) attachments upload through `DirectUploadsController`, which shadows the Active Storage engine's direct-upload endpoint. The engine's own controller is **unauthenticated** — it inherits `ActionController::Base`, not the app's `ApplicationController` — and mints signed storage-write URLs from client-declared metadata with no type or size gate. The shadow inherits `ApplicationController` (bringing `Authenticatable`, `Current`, and the global `rescue_from`s along for free): it requires a signed-in session, rate-limits per user, and enforces an allowlist (`IMAGE_CONTENT_TYPES` + PDF) and a 10 MB cap. Both knobs are constants on that controller and are THE place a fork widens or narrows rich-text uploads; Office formats stay out by default because they are a real parser surface.

Enforcement reality — what each check actually buys (panel, 2026-08-13):

- The declared **byte size is a hard ceiling**: it is baked into the signed token, and the disk service re-verifies content length + checksum on receipt, so the cap bounds the bytes that reach disk.
- The declared **content type filters honest clients only**: Active Storage re-identifies the real type from the stored bytes at attach time, where model validations judge it.
- **Attachment happens by signed GID** embedded in the submitted body — a blob's `attachable_sgid` is sufficient to attach it — so any *new* blob-creation path a fork adds must carry its own gate.

The `>= x.y.z` floor on the `rails` gem in the Gemfile is a security floor: it stops a fresh `bundle install` in a fork from resolving back onto a version patched for a known CVE. Dependabot rewrites that line on every Rails bump and will drop the floor, so `spec/code_smells/template_invariants_spec.rb` fails if the requirement ever admits a vulnerable release again.

## External Client Access

Projects can be opened to external clients via the `Clientside::` area. This is a distinct access axis from workspace membership.

### Access model

- Clients are standard authenticated `User` records — they pass through the same authentication stack (session, rate limiting, account locking) as internal users.
- A client's only foothold inside the workspace is a kept `ClientAccess` record linking them to a specific project. They are **not** `Membership` holders; they appear in no workspace Pundit policies and consume no member seat.
- The `Clientside::BaseController` calls `skip_onboarding_requirement` so clients are never funneled into the workspace onboarding wizard.
- The area never sets `Current.workspace`. Projects are resolved by slug AND by verifying a kept `ClientAccess` for the current user — slug knowledge alone is insufficient (`set_client_project` in `app/controllers/clientside/base_controller.rb`).
- When a project's `clientside_enabled?` flag is false, `ensure_clientside_enabled` redirects the client away even if their `ClientAccess` record still exists.

### Visibility scope

Clients can only see resources that are **both** published and explicitly shared: `Resource#client_visible?` returns `true` only when `shared_with_client? && published?`. Nothing else in the workspace is accessible — no other projects, no member lists, no workspace settings.

### Client invitation bearer-token protection

Client invitations use the same bearer-token invitation system as workspace invitations. `Invitation.consume!` enforces an `EmailMismatch` guard: if the invitation was addressed to a specific email and the redeeming user's proven email does not match, redemption is refused with `Invitation::EmailMismatch`. This prevents a leaked invite link from being claimed by a different email address (`app/models/invitation/acceptance.rb`). Additionally, `accept_client_invitation!` re-checks `clientside_enabled?` at acceptance time, so an invite cannot be redeemed after clientside has been turned off for the project.

## Production Recommendations

### Rack::Attack (IP-Level Rate Limiting)

For production deployments, add [Rack::Attack](https://github.com/rack/rack-attack) for IP-level blocking across controllers:

```ruby
# Gemfile
gem "rack-attack"

# config/initializers/rack_attack.rb
Rack::Attack.throttle("logins/ip", limit: 20, period: 1.hour) do |req|
  req.ip if req.path == "/session" && req.post?
end
```

### Top Secret (PII Filtering)

For apps handling personally identifiable information in free-form text (user-generated content, chat messages), consider [Top Secret](https://github.com/thoughtbot/top_secret) to filter PII before sending to external APIs or LLMs:

```ruby
# Gemfile
gem "top_secret"

# Filter user input before API calls
filtered = TopSecret.filter(user_input)
```

This is especially relevant for:
- `ActivityLog` metadata containing free-form text
- `Document` content processed by search indexes or AI features
- Any data sent to third-party analytics or monitoring

### Outbound Requests (SSRF)

The template makes exactly one outbound HTTP call today — a gravatar existence
check against a hardcoded host — so it ships **no** SSRF machinery. The moment
a fork adds its first **user-controlled outbound host** (webhook deliveries,
avatar-by-URL, link previews, OAuth discovery), that feature needs all of the
following, **in this order**:

1. **Scheme allowlist first.** An IP-range check never sees the scheme —
   `file://`, `gopher://`, and `ftp://` must be rejected before anything else:
   `return unless uri.scheme == "https"`.

2. **Host allowlist second, before any DNS resolution.** A pure string check
   on the parsed `uri.host` — exact match, or suffix with a leading dot.
   Naive `include?` fails both ways: `evil-gravatar.com` and
   `gravatar.com.attacker.net` each contain `gravatar.com`. Checking before
   resolution also means a non-allowlisted host never triggers a lookup, so
   the app can't be used as a DNS oracle and resolution timeouts can't burn
   worker time.

3. **Resolve, reject private ranges, then PIN the resolved IP.** Resolving
   and checking is not enough — a rebinding attacker answers the check with a
   public IP and the actual request with `10.0.0.1`. The defense is making
   the request to the address you checked:

   ```ruby
   http = Net::HTTP.new(uri.host, uri.port).tap do |h|
     h.use_ssl = true
     h.ipaddr = resolved_ip # rebinding defense — connect to the CHECKED address
   end
   ```

   For the resolve-and-reject step, port fizzy's `SsrfProtection` module
   (`app/models/ssrf_protection.rb` in basecamp/fizzy @ be42ca2, with its
   caller at `app/models/webhook/delivery.rb:111`) — the NAT64/Teredo/
   IPv4-mapped-IPv6 edge cases it handles are the parts hand-rolled versions
   get wrong. It is deliberately **not** vendored here while nothing calls it
   (an unexercised security primitive invites unpinned callers that are
   exactly as vulnerable as no check, while believing otherwise). The port
   plan and its trigger — first user-controlled outbound host — are recorded
   on template issue #658.

4. **Redirects: re-resolve, re-check, and re-pin on every hop — or refuse to
   follow them.** Pinning hop 1 and following a redirect unpinned is fully
   exploitable; fizzy sidesteps the problem by never following redirects.

5. **Rescue resolver errors explicitly.** DNS failures raise
   (`Resolv::ResolvTimeout`, `Resolv::ResolvError`, `SocketError`) — a caller
   that copies the happy path without those rescues turns any DNS hiccup into
   a 500.

6. **Background jobs only.** Resolution against external nameservers can take
   seconds; it never belongs on a request thread, and it hard-fails in
   egress-restricted environments.

### HTTPS and HSTS

Configure in `config/environments/production.rb`:

```ruby
config.force_ssl = true
config.ssl_options = { hsts: { subdomains: true, preload: true, expires: 1.year } }
```

### Responding to a Secret Exposure

Some vulnerabilities disclose anything readable by the app process — CVE-2026-66066 above is one. Upgrading closes the hole but does not undo an exfiltration that already happened. If your deployment ran an affected version while reachable by untrusted users, treat every secret the process could read as exposed and replace it:

1. `secret_key_base` — rotating it signs out every user and invalidates encrypted and signed cookies, signed global IDs, and existing Active Storage URLs.
2. The master key (`config/master.key` or `RAILS_MASTER_KEY`) and everything `config/credentials.yml.enc` decrypts. Re-encrypt under the new key with `bin/rails credentials:edit`. One entry inside the blob is different: `active_record_encryption.primary_key` rotates by listing the new key after the old one and re-saving records (Rails guide, "Rotating Keys"), but `deterministic_key` **cannot** rotate — Rails refuses a list. Replacing it means decrypting every deterministic column under the old key and re-writing under the new one in a one-off pass this template does not ship; until then, an exposed deterministic key means the addresses in `users.email_address`, `invitations.email`, and `magic_link_tokens.email` are recoverable from any dump taken while it was in use — as is `invitations.token` (also deterministic, for its `find_by` lookup and unique index), so working invitation accept/decline/block links are recoverable from that dump too, for as long as those invitations stay pending. `authentications.pending_invitation_token` (the parked copy of the same token, held non-deterministically because nothing looks it up by value) decrypts under the rotatable `primary_key` instead, so it isn't stuck the way the deterministic columns are — but until you actually rotate, it is exposed the same way everything else in this step is.
3. Storage service credentials (S3, GCS, Azure) if you moved off the local disk service.
4. Database credentials, if your database is not the bundled SQLite file.
5. API tokens and keys for every third-party service the app calls — OAuth client secrets, mail provider keys, error reporting DSNs.
6. Bearer tokens that may sit in the host's request logs (see *Bearer Tokens in Request Logs*): rotate every active workspace join link, and treat any magic-link, invitation, or verification token issued inside its lifetime as spent by requesting or sending a fresh one.

Replace secrets outright. Keeping the old value as a rotation fallback is only an intermediate step; do not leave an exposed secret in the rotation list.
