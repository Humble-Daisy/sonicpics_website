---
title: Notifications — Technical Reference
description: Architecture, broadcast pipeline, persistence schema, and operational concerns for the notifications system
keywords: notifications architecture noticed gem turbo streams broadcasts broadcaster indicator recipients gating idempotency value object pundit cleanup retention digest mailer quiet hours placeholder deleted record schema bullet half-open watermark read state audit trail activity log security event password passkey new device sign-in retention floor strict best-effort account activity actor rule self join granted_by onboarding grade deliver nil
---

# Notifications — Technical Reference

Implementation reference for the notifications subsystem. The end-user view of the same feature is in the **User Guide** version of this doc — switch the mode in the sidebar to view it.

## Stack at a glance

| Concern | Implementation |
|---|---|
| Event + recipient persistence | [Noticed v2](https://github.com/excid3/noticed) — `noticed_events` + `noticed_notifications` tables |
| Per-event delivery rules | Notifier subclasses under `app/notifiers/` |
| In-app real-time | Turbo Streams 4-target broadcast on `[user, :notifications]` channel via `NotificationBroadcaster` |
| Email delivery | `NotificationMailer` (per-event + `digest`); cadence on per-user `notification_preferences` |
| Per-user config | `NotificationPreferences` value object wrapping `user_preferences.notification_preferences` JSONB |
| Background jobs | `DigestMailerJob`, `NotificationCleanupJob` — cadence + queue in `config/recurring.yml` |
| Authorization | `NotificationPolicy` + `Settings::NotificationPreferencesPolicy` (Pundit) |

## Schema

### `noticed_events`

One row per discrete event. Polymorphic `record` association ties the event to whatever caused it (a `User`, an `Invitation`, a `Membership`, etc.).

Key column: `idempotency_key` — a `(notifier_class, record_id, minute_bucket)` string. A **partial unique index** on this column is the atomic source of truth for dedup; concurrent dispatches racing within the same minute lose to `ActiveRecord::RecordNotUnique`, which `ApplicationNotifier#deliver` rescues into the `:deduplicated` sentinel.

### `noticed_notifications`

One row per `(event, recipient)` pair. `recipient` is polymorphic (always `User` in v1). `read_at` is `nil` for unread.

| Column | Purpose |
|---|---|
| `event_id` | FK to `noticed_events` |
| `recipient_type` / `recipient_id` | Polymorphic recipient |
| `type` | STI shape — e.g., `PasswordChangedNotifier::Notification` |
| `read_at` | Nullable timestamp; the read/unread state and nothing else — a *return to me later* state, if one is ever built, gets its own column rather than a `read_at` reset |

There's a composite index `(recipient_id, read_at, created_at)` to back the `/account/notifications` index page (default sort + `?filter=unread`), the per-user unread breakdown that drives the bell indicator, and the cleanup job's `read_at < cutoff` scan.

### `user_preferences.notification_preferences` (JSONB)

The canonical per-user config. Shape (with database-level defaults applied automatically on row creation):

```json
{
  "notification_types": {
    "security": true,
    "account_access": true,
    "workspace_activity": true,
    "project_activity": true,
    "billing": true
  },
  "delivery_methods": {
    "in_app": { "enabled": true },
    "email":  { "enabled": true, "frequency": "instant" }
  },
  "quiet_hours": {
    "enabled": false,
    "start": "22:00",
    "end": "07:00",
    "active_days": ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
  },
  "retention_days": 90
}
```

A user with no `user_preferences` row at all still gets sane defaults because `ApplicationNotifier.preferences_for(user)` falls back to `UserPreferences.new.notification_preferences` (which materializes the schema default).

## Notifier subclasses

All inherit from `ApplicationNotifier` (which extends `Noticed::Event`). Each declares its `category` (drives preference opt-in/opt-out) and its `severity` (drives the bell indicator color) via DSL macros:

```ruby
class PasswordChangedNotifier < ApplicationNotifier
  category :security
  severity :danger

  deliver_by :email, mailer: "NotificationMailer", method: :password_changed,
             if: ->(recipient) { deliver_email_now? }

  notification_methods do
    def message = I18n.t("notifications.password_changed.message", user_name: recipient.full_name)
    def url     = main_app.settings_connected_accounts_path
  end
end
```

`category` stores as a `String` (compared against JSONB preference keys); `severity` stores as a `Symbol` (used to index into `NotificationBellHelper::SEVERITY_RANK`/`SEVERITY_CLASSES`). Default `severity` is `:info` when a subclass doesn't declare one.

| Notifier | Category | Severity | What it dispatches on |
|---|---|---|---|
| `PasswordChangedNotifier` | `security` | `danger` | `User#password_digest` change |
| `PasswordLockedNotifier` | `security` | `danger` | Failed password attempts lock the account (`User#locked_at` set) |
| `PasskeyAddedNotifier` | `security` | `danger` | Passkey enrollment (`Passkeys::Registration::CredentialsController#create`) |
| `SignInFromNewDeviceNotifier` | `security` | `danger` | Login from a previously-unseen browser fingerprint |
| `WorkspaceInvitationAcceptedNotifier` | `workspace_activity` | `success` | An invitee accepts the inviter's invitation |
| `WorkspaceInvitationDeclinedNotifier` | `workspace_activity` | `info` | An invitee declines |
| `WorkspaceInvitationResentNotifier` | `account_access` | `info` | Inviter manually resends |
| `WorkspaceInvitationExpiringSoonNotifier` | `account_access` | `warning` | Sweep job finds invitations within 24 hours of expiry |
| `WorkspaceRoleChangedNotifier` | `account_access` | `info` | Owner changes a member's role |
| `WorkspaceCreatedNotifier` | `workspace_activity` | `success` | Someone creates a workspace through `Workspace.create_owned` |
| `WorkspaceMemberAddedNotifier` | `workspace_activity` | `success` | New member joins, or a removed one is re-admitted (fans out to all owners except whoever performed the add) |
| `WorkspaceMemberRemovedNotifier` | `account_access` | `warning` | A membership is discarded — an owner removing someone, or a member leaving. In-app to the removed member and the owners (minus whoever acted); email to the removed member only |
| `WorkspaceJoinedNotifier` | `workspace_activity` | `success` | Someone admits themselves through an open join link — the joiner's own orientation, since the actor rule drops them from `WorkspaceMemberAddedNotifier` |
| `ProjectMembershipChangedNotifier` | `project_activity` | `info` | Project member role changed |
| `WorkspaceCapacityApproachingNotifier` | `billing` | `warning` | Sweep job finds a workspace approaching its plan limit |
| `WelcomeNotifier` | `account_access` | `info` | A real registration completes — `MagicLinkCallbacksController#create`, or either signup branch of `OauthLink` |

**Member removal is `account_access`, not `workspace_activity`, on purpose.** Removal used to be silent; a removed member found out by hitting a wall (#933). The category is the user's opt-out axis, and `workspace_activity` is the chattiest one, carrying every join and every workspace created. A member who had muted it would learn they lost access through neither channel, which is the silence this notifier exists to end. `WorkspaceRoleChangedNotifier` sits in `account_access` for the same reason: it changes this person's access, it is not workspace news.

Its copy varies by channel, not by reader. The in-app row is third-person event-log voice for everyone who receives it, the removed member included, and it branches on the event: a member who removed themselves "left", anyone else "was removed". The email is the only second-person surface, and only the removed member gets one. Its link goes to the workspaces index, not the workspace: the workspace is exactly where the removed member can no longer go, the index is the one destination true for every recipient, and reading nothing off the record means a deleted workspace cannot break it.

### Category → notifier types

`ApplicationNotifier.notification_types_for(category)` returns the `Noticed::Notification` STI type strings for that category — used by `NotificationsController#index` for `?category=foo` filtering, and by `NotificationCleanupJob` for retention-floor enforcement. The suffix-free variant `ApplicationNotifier.notifier_class_names_for(category)` returns the parent Notifier class names.

### Preference resolution and the missing-row fallback

`ApplicationNotifier.preferences_for(user)` resolves a `NotificationPreferences` object for any user, **including users with no persisted `user_preferences` row**: it falls back to wrapping `UserPreferences.new.notification_preferences`. Why a transient record instead of a Ruby constant? The `notification_preferences` JSONB column carries a database-level default containing the canonical permission matrix (see `db/schema.rb`), and Rails populates column defaults on the in-memory record — so the schema default stays the single source of truth. Hard-coding the matrix in Ruby would create a second copy that could silently drift from the schema.

This replaced an earlier behavior that wrapped `nil`, which made every category except `security` answer `false` from `deliver_now?` — a silent default-deny posture for freshly-created users with no preferences row yet. Incorrect, since the schema default permits in-app delivery for every category.

The method is available as both a class method (backing the per-recipient `recipient_pref` shim inside `notification_methods`) and an instance method (used by class-level `recipients` resolvers).

### In-app gating lives in `recipients`

Noticed 2.9.x deprecates the `:database` delivery method — notification rows are auto-saved by the deliver pipeline itself, so there is no delivery-method conditional to hang an "is in-app enabled for this recipient?" check on. The only place to prevent a `noticed_notifications` row from ever existing is **recipient resolution**: the notifier's `recipients` block filters out users whose `<category>.in_app` preference is `false` (which, for non-security categories, also covers quiet hours via `deliver_now?`). This is the pattern for every notifier that respects in-app preferences — `WorkspaceMemberAddedNotifier`, `WorkspaceCapacityApproachingNotifier`, `WorkspaceCreatedNotifier`, `WorkspaceJoinedNotifier` and `WelcomeNotifier` all declare a `recipients` block and are dispatched with `deliver(nil)` so the block, not the caller's argument, resolves recipients. Combined with the missing-row fallback above, users without a preferences row are correctly treated as opted-in at the column-default level instead of being silently filtered out of every dispatch.

**The `deliver(nil)` invariant, both directions.** `Noticed::Deliverable#deliver` is `recipients ||= evaluate_recipients` — `noticed-3.0.0`, `app/models/concerns/noticed/deliverable.rb:87`. An explicit recipient does not *add* to the block; it *replaces* it, and the block never runs. So:

- A notifier that **declares** a `recipients` block must be dispatched with `deliver(nil)`. Passing a recipient skips `permitted_in_app` — delivering to someone who opted out or is inside quiet hours — and skips the actor exclusion below. Nothing raises, nothing is logged; the preference is just quietly ignored.
- A notifier that declares **no** block must be dispatched with an explicit recipient. `deliver(nil)` there resolves to zero recipients, so `ApplicationNotifier#deliver` returns `:skipped` and writes no rows at all — a dispatch that silently does nothing.

That empty-set guard lives in `ApplicationNotifier#deliver`, not in the gem. `Noticed::Deliverable#deliver` calls `save!` **unconditionally** — only its `notifications.insert_all!` is guarded by `.any?` — so before the guard a zero-recipient dispatch still wrote the `noticed_events` row *and* consumed its minute-bucket idempotency key. That is reachable through a `recipients` block, not just through a mis-dispatched notifier: the actor exclusion below can leave a candidate set empty (a single-owner workspace whose owner acts on their own membership), and a genuine dispatch on the same record inside that minute then deduplicated away with nobody ever notified.

Neither failure is visible at runtime, so both directions are fenced by `spec/code_smells/notifier_recipients_block_dispatch_spec.rb`, which scans every `SomeNotifier.with(...).deliver(...)` in `app/` and matches it against whether that notifier declares a block.

Genuinely per-notifier specifics:

- **`WorkspaceMemberAddedNotifier`** (fires on `Membership` create, and on the undiscard that re-admits a removed member) is dual-recipient: (1) the added user, (2) all workspace owners, `.uniq`'d so an added user who is already an owner isn't double-notified — minus whoever performed the add. Nobody is notified about their own action, so an owner who adds someone hears nothing, and an owner-inviter gets only `WorkspaceInvitationAcceptedNotifier` rather than that plus "X joined". On the self-join paths there is no granter at all, so the actor is the joining user themselves — they hear nothing here, and the owners still learn that someone joined. An open-link joiner is oriented by `WorkspaceJoinedNotifier` instead; the `:shared` preset's signup join is not, because `WelcomeNotifier` already is. See *The actor rule* below. The actor arrives as the `actor:` **param**, never off `record.granted_by`: that is a non-persisted `attr_accessor`, so an exclusion reading it back off the record would exclude nobody the moment recipient resolution stopped seeing the in-memory row. The block preloads `:preferences` in one query — per-user `user.preferences` access inside the filter is otherwise an N+1 across the candidate set (Bullet caught it). Email goes **only** to the added user: a `before_enqueue` lambda `throw(:abort)`s unless `recipient_id == event.record.user_id` AND the added user's `workspace_activity.email` pref is `true`. Comparing on the `recipient_id` column (not the loaded association) avoids a per-row association load that Bullet would flag when Noticed's `EventJob` iterates `event.notifications`. Owners never get an immediate email — the digest pipeline is their intended email fallback.
- **`WorkspaceCapacityApproachingNotifier`** (fired by `WorkspaceCapacitySweepJob` when a workspace reaches ≥ 80% of a plan quota; v1 sweeps only the `members` metric) sends to workspace owners filtered by `billing.in_app` — the category is deliberately `billing`, not `security`, so quiet hours suppress these. It declares `dedup_bucket :day` + `dedup_seed { params[:metric] }`: the default one-minute bucket is wrong for a recurring sweep (cadence in `config/recurring.yml`), so the key is scoped per `(workspace, metric)` with a **day** bucket. Repeat sweeps in one day dedupe to a single alert; distinct metrics for the same workspace on the same day don't collapse onto each other; the next day's sweep gets a fresh key and delivers again if the workspace is still over threshold.

- **`WelcomeNotifier`** is the only notifier dispatched from the HTTP registration path rather than a model callback. `User` has `after_create :onboard_workspace`, so a callback-fired welcome would ride every `create(:user)` in the suite and shift every notification count in it; the dispatch sites are `MagicLinkCallbacksController#create` (after the token is confirmed consumed, since a concurrently-consumed token rolls the signup back while `commit_signup_atomically` still returns `true`) and both signup branches of `OauthLink`, which no factory reaches. In-app only: someone who just registered is already in the app, and signup's own mail should not compete with a welcome email.

- **`WorkspaceJoinedNotifier`** is the self-join counterpart to the welcome email an invited member gets. Because the joiner is the actor, excluding them from `WorkspaceMemberAddedNotifier` also removes the notification row the welcome email rides on — this notifier is what keeps a new member oriented without weakening the actor rule. It fires from `Membership`'s `after_create_commit :notify_self_joined` / `after_update_commit :notify_self_rejoined` (distinct filter names for one body: the `:commit` chain dedups by filter name, so reusing one would replace the other), both gated on the non-persisted `self_join` marker at its `true` grade. See *The actor rule* below for why that marker is deliberately not `granted_by: user`, and why the `:onboarding` grade — the `:shared` preset's signup join — fires nothing here. In-app only, on `WelcomeNotifier`'s reasoning: the joiner clicked join seconds ago and is being redirected into the workspace.

### The actor rule — nobody is notified about their own action

Recipient resolution drops whoever performed the action (the 37signals rule). An owner who adds a member hears nothing about their own add, and a self-joiner is never told, in the third person, that they joined.

The actor travels as a **param** — `WorkspaceMemberAddedNotifier.with(record: membership, actor: …)` — and is never read back off the record inside the `recipients` block. Every source of the actor is a non-persisted `attr_accessor` on `Membership`, so an exclusion keyed on `record.granted_by` (or `record.removed_by`) would exclude nobody the moment recipient resolution stopped seeing the in-memory row: silently, with nothing failing.

`Membership` carries **three** markers. Two of them describe how a membership arrived, and keeping *those* apart is the point:

| Marker | Question it answers | Where it lands |
|---|---|---|
| `granted_by` | who granted this membership | the `membership.created` activity row's `granted_by` metadata, **and** the notification actor |
| `self_join` | nobody granted it — the joining user acted | the notification actor only |
| `removed_by` | who removed this member | the notification actor only |

`removed_by` sits on the other transition entirely — it reaches the model as an argument to `Membership#deactivate!` and feeds `WorkspaceMemberRemovedNotifier`, where it decides both who is excluded and whether the row reads "was removed" or "left". It is unrelated to the pair below, and shares nothing with them but the actor-as-param discipline.

The tempting simplification is to collapse the arrival pair, since a self-join is arguably "granted by the joiner". Don't: `granted_by` is audit provenance. Writing the joiner in as their own granter makes the audit row for a self-join **indistinguishable from an admin grant** — the one distinction that row exists to record. What ships records no granter for a self-join, which is both true and unambiguous.

`granted_by` and `self_join` are also mutually exclusive, and refused rather than merely documented: `Membership.reject_conflicting_provenance!` raises `ArgumentError` when a caller hands both to `Workspace#admit` or `Membership#reactivate!`. Before that guard, `self_join` silently won the actor selection while `granted_by` still reached the audit row — a row naming a granter for something the same row records as ungranted.

`self_join` has two grades, because "who acted" and "does the joiner need telling where they landed" are separate questions:

- **`true`** — a join the user chose, through an open link. They are excluded from `WorkspaceMemberAddedNotifier` (they are the actor) and oriented by `WorkspaceJoinedNotifier` instead; the owners still learn that someone joined.
- **`:onboarding`** — the membership `User#join_shared_workspace` creates at signup under the `:shared` preset. The exclusion applies; the orientation notice does not. `WelcomeNotifier` already lands in the same second, the `:personal` sibling path (`User#create_personal_workspace`) raises no workspace notification either, and under `:shared` the workspace *is* the app — "you joined Acme" restates the redirect the user just followed.

A membership created with **neither** marker is not neutral. The actor resolves to `nil`, nobody is excluded, and the new member is told about their own join — which is exactly what `User#join_shared_workspace` did before it declared its stance. `spec/code_smells/membership_creation_declares_actor_stance_spec.rb` fails on any creation site in `app/` or `lib/` that names neither, with a reviewed allow-list for the first-owner seeds (a workspace's very first owner-membership has nobody to notify, so `Membership#workspace_has_other_owners?` skips the fan-out entirely).

**Every in-memory instance that saves inside the transaction must carry the markers.** Rails, not the caller, picks which instance of a row runs the commit callbacks: with `run_commit_callbacks_on_first_saved_instances_in_transaction` set to `false`, it is the *last* one saved. `Workspace#admit` can be handed a second instance of a row the same transaction just inserted — under the `:shared` preset, `User#onboard_workspace` creates a placeholder Member membership and `Invitation#accept!` reconciles its role through `admit`, both inside `Signupable#commit_signup_atomically` — so `admit` stamps `granted_by` and `self_join` onto that `existing` instance too. Leaving it markerless silently dropped the actor rule: the granter was told about their own grant, and a self-joiner was told they had joined.

The same discipline gates `WorkspaceCreatedNotifier`: it fires only when the non-persisted `created_by` marker is set, which `Workspace.create_owned` — the one path a person creates a workspace through — does and nothing else does. Seeds, fixtures, and the signup-time personal workspace stay silent; a fork adding a creation site opts in by setting the marker.

### Email gating and the `:digest` sentinel

An email is one of three fates: deliver now, drop, or wait for `DigestMailerJob` to pick it up. The gate is `deliver_email_now_for?(user)`, which is strictly "send the instant email to this user now" — it answers `false` both for an opt-out/DND drop and for the digest deferral, so the digest frequency choice can never be defeated by an accidental truthiness check. (`recipient_pref(:email)` still reports the tri-state — `true` / `false` / `:digest` — as an introspection surface.)

`deliver_email_now?` is the no-argument form for the common case — "is this notification's own recipient allowed an instant email?" — and it answers from the notification's `recipient_id` column, never from the `recipient` association.

Prefer the explicit form in a `before_enqueue` that has already narrowed the fan-out to one known user — typically with `throw(:abort) unless recipient_id == event.record.user_id`. At that point the surviving recipient *is* `event.record.user`, which the guard has already loaded, so asking about it directly is equivalent — and cheaper. `deliver_email_now?` answers from the event's permitted-recipient set, which materialises **every** recipient and their preferences to decide about one; a guard that has already narrowed the fan-out to a single known user should ask about that user and load one row. Both member notifiers do, and their `EventJob` measures flat at four queries with two owners and with eight.

A notifier whose email leg has **no** narrowing guard asks the gate once per recipient, and that used to grow with the fan-out — one `users` select plus one `user_preferences` select per recipient, inside a single `EventJob` (#936). It no longer does. `ApplicationNotifier#email_permitted?` resolves the event's whole permitted-recipient set in one pair of queries and memoises it for the job, so the per-recipient gate is a `Set` membership test on a column value. Noticed offers no hook to preload `:recipient` on the relation its `EventJob` iterates, which is why the set is resolved by id rather than by preloading the notification rows — and preloading them would leave `recipient` eager-loaded and unread on every narrowing-guard notifier, which is Bullet's unused-eager-loading shape.

### `render_safe_or_placeholder` — the deleted-record contract

Any notifier `message`/`url` body that traverses associations or reads attributes off `event.record` should run inside `render_safe_or_placeholder`. It rescues exactly two shapes, logs at `info`, and renders the `notifications.placeholder` I18n string:

- `ActiveRecord::RecordNotFound` — the resource was destroyed mid-render
- `NoMethodError` **only when the exception's receiver is `nil`** — a chained association is now nil

Everything else propagates: typos and missing methods on non-nil receivers are real bugs and must not be masked as placeholders.

Know the contract's edge: only deletion shapes that surface as a *nil receiver* are caught. `resource.invitable.name` where `invitable` is gone raises `NoMethodError` with `receiver == nil` — caught. A stale FK pointing at a deleted record that still loads as a stub object won't produce a nil receiver and may bubble up as `RecordNotFound` (caught) or some other exception (not caught). `I18n::InvalidLocale` is also NOT rescued — which is why `recipient_locale` validates the stored locale against `I18n.available_locales` before handing it to `I18n.t` (a stored-but-retired locale would otherwise 500 the surface rendering the message).

## Bell indicator + helper

There is no dropdown panel and no standalone bell link. The unread indicator is a small severity-colored **dot** rendered by `shared/_notifications_indicator`: the desktop avatar button carries it at its bottom-right, and the mobile hamburger button carries its twin. The dot's color encodes the highest-severity unread; the numeric `[N new]` badge lives in the user-menu **Notifications** row, which is also the navigation path to `/account/notifications`. The dot itself is purely decorative (`aria-hidden`) — the accessible announcement lives elsewhere (see the broadcast pipeline below).

### `User#unread_notification_breakdown`

One indexed `GROUP BY` query that returns `{ notifier_class_name => unread_count, ... }` for the user — count + severity-source data in a single DB hit:

```ruby
def unread_notification_breakdown
  notifications
    .where(read_at: nil)
    .joins("INNER JOIN noticed_events ON noticed_events.id = noticed_notifications.event_id")
    .group("noticed_events.type")
    .count
end
```

### `NotificationBellHelper`

The helper owns view-token mapping + severity orchestration. The three public surfaces consumers care about:

| Method | Returns | Used by |
|---|---|---|
| `unread_notification_summary(user)` | `{ count:, severity: }` (severity nil when count zero) | The three frame-rendering broadcasts (avatar indicator, hamburger indicator, menu count row); passed in as a `summary:` local from `NotificationBroadcaster` to avoid redundant queries |
| `notification_bell_classes(severity, variant: :icon)` | `{ icon: "text-<severity>" }` for `:icon`; a dot class (`SEVERITY_DOT_CLASSES`) for `:dot` | The indicator partial (`variant: :dot`) — maps severity to the saturated `--color-{severity}` token already used by toasts; `variant:` selects the icon-tint vs. dot-indicator form |
| `avatar_button_aria_label(user, summary = …)` | I18n-composed string ("User menu for Nell. 3 unread notifications, including a security alert.") | Retained from the retired standalone bell; the current avatar button carries a static identity-only label (`navigation.user_menu_label_simple`), so unread phrasing no longer rides the button's accessible name |

`SEVERITY_RANK = { danger: 4, warning: 3, info: 2, success: 1 }` — higher rank wins when multiple severities are unread. `canonical_severity(severity)` clamps any input to one of the four canonical values (defensive coverage for non-production paths; production is already guarded by `ApplicationNotifier.severity`'s DSL).

The helper uses `extend self` so every method is callable BOTH as a module method (`NotificationBellHelper.unread_notification_summary(user)`, used by `NotificationBroadcaster` which has no view context) AND as a public instance method when mixed into a view. Unlike `module_function`, instance-mixed methods stay public, so `helper.foo` works in specs.

### Forced-colors fallback for AAA

Windows High Contrast / `forced-colors: active` overrides author colors with system colors, so the dot's severity fill collapses to a single system color. The indicator partial forces `bg-[Highlight]` under `forced-colors:` so the dot stays visible (WCAG 1.4.11 non-text contrast under that accommodation), and a `drop-shadow` filter keyed to `--color-surface-raised` separates it from arbitrary avatar backgrounds. The dot also always renders — visibility is `opacity-100`/`opacity-0`, so mark-all-read fades it out (`motion-safe:` only) instead of removing the element.

## Idempotency

Every event carries an `idempotency_key` populated by `ApplicationNotifier#populate_idempotency_key` in a `before_create` callback. Default shape:

```
{NotifierClass}_{record_id}_{minute_bucket}
```

Where `minute_bucket = Time.current.to_i / 60`. This means:

- The same notifier + same record dispatched **within the same minute** dedupes to one event
- A dispatch at second 59 and a retry at second 0 of the next minute **both succeed** (different buckets)
- The DB partial unique index enforces the dedup atomically; there's no app-level SELECT-then-INSERT race

Notifiers tune their key declaratively — key assembly itself stays in the one base callback:

- `dedup_bucket :day` swaps the minute bucket for an ISO-date bucket (right for recurring sweeps: `WorkspaceInvitationExpiringSoonNotifier`, `WorkspaceCapacityApproachingNotifier`)
- `dedup_seed { ... }` contributes extra segments between the record id and the bucket, instance-exec'd on the event so it can read `params`/`record` (`SignInFromNewDeviceNotifier` folds in the browser digest; `WorkspaceCapacityApproachingNotifier` the metric)

Callers can pass `idempotency_key: "custom"` to override the default. If neither `:record` nor an explicit key is supplied, `populate_idempotency_key` raises `ArgumentError` — loud failure beats silent dedup-collapse across distinct events.

`ApplicationNotifier#deliver` returns sentinels:

- `:skipped` when the recipient set resolves empty — the dispatch returns **before** `super`, so no event row is written and the bucket key stays unconsumed
- `:delivered` on first-send
- `:deduplicated` on `ActiveRecord::RecordNotUnique`

`:skipped` exists because the key is minted in a `before_create` on the event row, and the gem writes that row even with zero recipients (see *The `deliver(nil)` invariant* above). Keying the bucket on the recipient set would be the alternative and is worse: it makes the key non-deterministic across retries of the same dispatch.

Callers (e.g., `Workspaces::Invitations::ResendsController#create`) branch on this to choose flash copy. A caller that branches on `:deduplicated` treats `:skipped` like `:delivered` unless it says otherwise — which is correct where the dispatch carries an explicit, known-present recipient and `:skipped` cannot occur.

## Coalescing — not built; the recipe

Idempotency answers "is this the same dispatch?". Coalescing answers "should the recipient experience distinct events as one item?" — every event still exists, the attention row is shared. Nothing below is implemented. The trigger is a notifier whose volume is not bounded by a human action (#807); the current roster is account and security events, so the template does not carry the machinery speculatively. When the trigger fires, the write path must carry all of the following. Each was found necessary in the 2026-08-25 lifecycle design, and dropping one produces a specific bug named alongside it.

- **A unique key namespaced by notifier class.** Two notifiers coalescing on the same record must not share a row.
- **A single-statement counter increment**, `coalesced_event_count = coalesced_event_count + 1`, on a nullable column populated only for coalescing rows. The name `unread_count` was rejected: it double-represents read state and collides with what `User#unread_notification_breakdown` means.
- **A `read_at` reset on each coalesced arrival**, so the item returns to unread.
- **A mark-read compare-and-swap keyed on `event_id`.** A stale `event_id` re-renders the row instead of marking a newer arrival read.
- **`RecordNotUnique` scoped to the coalescing insert**, distinct from the outer idempotency rescue that returns `:deduplicated`.
- **The gem-internal write order, pinned to noticed 3.0.0:** `validate!` → transaction → `notifications_count=` → `save!` → `insert_all!` → `EventJob` enqueue. The enqueue must follow the `event_id` re-point, or email fans out over the wrong `has_many`.
- **One decision between manual `notifications_count` assignment and a counter cache.** Both at once double-count.
- **The write path returns the touched row ids**, so `broadcast_notifications_arrival` does not silently no-op for a re-pointed row.
- **`mark_all_read` zeroes the counter.**
- **The bell decides once whether it counts rows or sums counters.**
- **A `category :security` notifier that declares coalescing raises at boot.** Security events are never merged.
- **The key is record plus recipient set, not record alone.** The actor rule above excludes the actor from recipients, and a member re-admitted to a workspace is notified again, so the same record can legitimately produce two items with different audiences.

## Dispatch reliability

What is atomic is the ledger: `Noticed::Deliverable#deliver` writes the event row, its `idempotency_key`, and every recipient's notification row in one transaction. What is *not* atomic is the delivery job — noticed enqueues `Noticed::EventJob` after that transaction returns, and Solid Queue writes to a separate SQLite database in production, so it never could be. If the enqueue fails (Solid Queue's database busy past its timeout, a full disk) or the process dies in the gap, the recipient sees the notification in the bell, the key is burned so a retry inside the same bucket dedupes away, and the email and broadcast legs never run.

So the job records its own arrival. A `before_perform` callback registered in `config/initializers/noticed.rb` stamps `noticed_events.dispatched_at` at the **start** of `Noticed::EventJob`, and `NotificationDispatchReconcileJob` re-enqueues any event still carrying NULL five minutes later (see [Background jobs](#background-jobs)).

Stamping at the start, not the end, is what keeps the sweep safe: an event whose job was *claimed* is already stamped, so the reconciler covers only the never-enqueued gap and can never re-run an event whose delivery legs already fanned out.

**What the watermark does not cover**, stated plainly because it is easy to assume otherwise: a job that was claimed and then *raised*. The gem ships no retry policy — only `discard_on ActiveJob::DeserializationError` — so `config/initializers/noticed.rb` registers one: three attempts with a growing delay (#1065). Retrying re-runs `perform`, which is **not idempotent** — the fan-out is 1-3 delivery legs and a recipient may see a duplicate email. That trade is deliberate and the smaller harm: a duplicate is visible and annoying, a silently dropped security notification is neither.

Two things remain uncovered. A job that exhausts its three attempts lands in `solid_queue_failed_executions`. So does a pruned worker process's claimed execution — Solid Queue *fails* those rather than releasing them, which no retry policy can see. The reconciler is not that safety net and cannot be: the row is stamped, so it is invisible to the sweep by design. What it does instead is **count** them: when any `Noticed::EventJob` execution is sitting in that table, the run ends by logging a warning naming how many (`report_failed_event_jobs`); a clean run logs nothing for it. This app ships no Mission Control UI, so that warning is the whole signal (#1266).

## Broadcast pipeline

The Turbo Streams layer is the cross-tab + arrival real-time backbone.

### Subscription

Every authenticated page subscribes via the layout:

```erb
<%= turbo_stream_from [Current.user, :notifications] %>
```

### The four broadcasts

`NotificationBroadcaster.refresh_for(user, announcement_key:)` (in `app/lib/notification_broadcaster.rb`) issues a four-target broadcast per call. Each frame target is an independent slim partial rendered into its own `<turbo-frame>`, so the surfaces refresh atomically without rewiring unrelated chrome.

1. **`notifications_indicator_avatar`** — the severity-colored dot on the desktop avatar button (`shared/_notifications_indicator`, `surface: :avatar`)
2. **`notifications_indicator_hamburger`** — the dot's twin on the mobile hamburger button (same partial, `surface: :hamburger`)
3. **`notifications_menu_count_frame`** — the `[N new]` badge inside the user-menu **Notifications** row (`shared/_user_menu_notifications_row`)
4. **`notifications-live`** — the page-level `aria-live="polite"` region; content is `I18n.t(announcement_key)` (`notifications.bell.arrival_announcement` or `notifications.bell.read_state_announcement`)

All four use `broadcast_update_to`, never `broadcast_replace_to`. The partials render each frame's **contents**, not the frame element itself — `replace` would swap the whole `<turbo-frame>` away, so repeat broadcasts couldn't re-target it and the surfaces would freeze after the first refresh. `update` swaps the inner content and keeps the frame addressable for the next refresh.

Why four targets: an earlier revision (D1) broadcast a standalone header bell — severity glyph plus a broadcast sr-only phrase inside the bell link's accessible name. That label frame is retired deliberately. The avatar and hamburger buttons now carry **static, identity-only** `aria-label`s; notification semantics are exposed through the user-menu Notifications row and the `aria-live` region instead. The enduring constraint: broadcast frames and live regions stay **outside** a focusable control's accessible-name path, so a control's name never mutates under an AT user mid-session.

Each broadcast runs in its own `safe_broadcast` rescue scope. A failure on ONE surface must NOT abort the others: the real failure mode this prevents is a transient cable adapter hiccup or a partial-rendering exception in an early broadcast silently dropping the rest of the refresh, leaving the UI stale. Each failed broadcast is `Rails.logger.warn`'d and `Rails.error.report(handled: true)`'d with a `source: "NotificationBroadcaster.<surface>"` context tag (`indicator_avatar`, `indicator_hamburger`, `menu_count_row`, `aria_live`), so a cable outage is visible per-surface. Those reports reach the log through the subscriber in `config/initializers/error_subscriber.rb`; sending them to a real error tracker is a fork's job — add your tracker as a second subscriber and the logging one keeps working alongside it.

Performance: the unread breakdown summary is computed ONCE at the top of `refresh_for` and passed to each receiving partial as a `summary:` local — avoids the redundant `unread_notification_breakdown` queries that would otherwise fire, one per partial that needs it.

### Two call sites

| Caller | When | Announcement key |
|---|---|---|
| `ApplicationNotifier#broadcast_notifications_arrival` (after_create_commit on the event) | New notification arrives | `arrival_announcement` |
| `Settings::NotificationsController#broadcast_bell_refresh` (private), called from `update`; `Settings::NotificationReadingsController#create` (mark all read) and `Settings::Notifications::ReadingsController#create` calls `NotificationBroadcaster.refresh_for` directly for the same reason | Read-state mutation | `read_state_announcement` |

Both flow through `NotificationBroadcaster.refresh_for` — no duplicate broadcast code lives anywhere else. The fan-out in `broadcast_notifications_arrival` iterates `User.where(id: recipient_ids).find_each` so per-user broadcast failures are isolated (one bad user can't poison the rest).

### Why hook on `Noticed::Event`, not `Noticed::Notification`

Noticed v2 uses `notifications.insert_all!` to fan out per-recipient rows — that bulk insert bypasses ActiveRecord callbacks on the `Notification` class. So `after_create_commit :broadcast_notifications_arrival` lives on `ApplicationNotifier` (the Event class), and the method queries `Noticed::Notification.where(event_id: id, recipient_type: "User").pluck(:recipient_id)` to find the rows that the bulk insert created.

### Frame targets in the DOM

| Frame ID | Lives in | Contents rendered by |
|---|---|---|
| `notifications_indicator_avatar` | `shared/_user_menu_avatar_button.html.erb` — a positioned sibling of the avatar image inside the button, outside its accessible-name path | `_notifications_indicator.html.erb` (`surface: :avatar`) |
| `notifications_indicator_hamburger` | `shared/_header.html.erb` — inside the mobile hamburger button, same sibling pattern | `_notifications_indicator.html.erb` (`surface: :hamburger`) |
| `notifications_menu_count_frame` | `shared/_user_menu.html.erb` — wraps the Notifications row | `_user_menu_notifications_row.html.erb` |
| `notifications-live` | `shared/_layout_tail.html.erb` — page-level `aria-live="polite"` region | Plain text content via `broadcast_update_to` |

The buttons themselves are OUTSIDE every broadcast frame — they're stable focusable elements. Only the decorative dot and the count badge swap on broadcast, so clicks landing mid-broadcast still hit a live target.

One trap inside `notifications_menu_count_frame`: the Notifications-row link must carry `data-turbo-frame="_top"`. Without it the link navigates its enclosing frame, and the index response has no matching frame — Turbo shows "Content missing".

### Cross-tab read-state sync

The tab that performs a read-state mutation gets its own surfaces refreshed by the direct Turbo Stream response; the broadcasts exist to cover every OTHER tab the user has open. The contract, pinned by `spec/requests/settings/notifications_spec.rb`: every read-state mutation (`update`, `mark_all_read`, `open` via the `readings` resource) must fire `broadcast_update_to` on the `[user, :notifications]` channel for all three frame targets — `notifications_indicator_avatar` (the dot + its severity), `notifications_indicator_hamburger` (its twin), and `notifications_menu_count_frame` (the count badge) — plus the `aria-live` announcement. Each frame is independent, so the surfaces update in isolation: the count badge re-renders even when a dot is already current. `open` on an already-read notification is an idempotent no-op — zero broadcasts.

## NotificationPreferences value object

`app/lib/notification_preferences.rb` wraps the JSONB hash with typed accessors. The two methods you'll touch most:

### `deliver_now?` / `defer_to_digest?` — the decision surface

Two strict predicates, both `(category:, channel:)`: `deliver_now?` is "send through this channel right now"; `defer_to_digest?` is "email queued for the digest pipeline" (never true for in-app or security). They share one private decision tree (`allow?` — the tri-state encoding never leaves the object):

1. Reject unknown category/channel pairs (deny)
2. If `category == "security"` → deliver (with one exception: if `channel == "email"` and email is disabled, deny — a user who turned off all email accepts that security alerts won't email; in-app remains always-on)
3. If `notification_types[category] != true` → deny
4. If `delivery_methods[channel].enabled != true` → deny
5. If `channel == "email"` and frequency is not `"instant"` → defer to digest (`DigestMailerJob` picks it up)
6. If `quiet_hours_active?` → deny (non-security only; security already delivered in step 2)
7. Otherwise → deliver now

### `quiet_hours_active?(now: Time.current)`

Reads the user's timezone (or falls back to `Time.zone`), checks today's day-of-week against `active_days`, then evaluates the time-of-day window. Same-day windows (`s <= e`) use `s <= cur < e`; overnight wraps (`s > e`) use `cur >= s || cur < e`. **Empty `active_days` means quiet hours never apply** — a deceptive state the UI surfaces via a Stimulus-driven warning.

That combination — quiet hours `enabled` with zero day chips checked — is deceptive because the form's toggle reads "Enabled" while the runtime treats quiet hours as never active. The preferences form mounts the `quiet_hours_warning` Stimulus controller, which listens for bubbled `change` events across the quiet-hours fieldset (and re-checks on `connect()` so the initial render matches saved server state); whenever the toggle is on and no day is checked, it unhides a warning paragraph. Without it, a user could save that contradictory configuration and walk away believing quiet hours are active when they aren't.

### `merge(changes)`

Validates a partial-change hash (the shape the preferences form posts), coerces strings to booleans + integers, and returns a NEW value object with the changes deep-merged in. Raises `NotificationPreferences::InvalidChange` on any validation failure — the controller catches and responds 422. **The receiver is unchanged on failure** — no half-applied state.

## Controllers

| Controller | Routes | Notes |
|---|---|---|
| `Settings::NotificationsController` | `index`, `update` (read-state toggle) | Pundit-gated; calls `broadcast_bell_refresh` on every read-state mutation |
| `Settings::NotificationReadingsController` | `create` (mark all read) | Pundit-gated (`mark_all_read?`); one atomic `update_all`, then `NotificationBroadcaster.refresh_for` |
| `Settings::Notifications::ReadingsController` | `create` (open-and-mark-read, POST-only via the nested `reading` resource) | Pundit-gated on `NotificationPolicy#open?`; the old mutating GET `:open` is gone (#686) |
| `Settings::NotificationPreferencesController` | `edit`, `update` | Delegates validation to `NotificationPreferences#merge`; rescues `InvalidChange` → 422 |
| `Settings::Preferences::TimezonesController` | `update` | Beacon-path returns 204; explicit-user path (`override=true`) returns Turbo Stream that closes the drawer + announces "Timezone updated" |

## Pundit policies

| Policy | Notes |
|---|---|
| `NotificationPolicy` | Per-record policy gates `update?`/`open?` (both by `record.recipient_id == user.id`); collection-level `index?`/`mark_all_read?` require only a signed-in user. `Scope` filters all of `Noticed::Notification` to the current user |
| `Settings::NotificationPreferencesPolicy` | Trivial — `edit?`/`update?` both return `user.present?` |
| `Settings::ThemePreferencesPolicy` | Same shape |
| `Settings::TimezonePolicy` | Same shape |

The preference policies look "decorative" (always-true for an authenticated user), but they're the gate that protects against future actions accidentally bypassing authorization — adding a new `:id`-taking action to any of these controllers will still fail-closed.

## Background jobs

Both scheduled in `config/recurring.yml` under the `production:` key — that file is the source of truth for cadence and queue assignment; the values are deliberately not repeated here. Not active in development/test by default.

### `DigestMailerJob`

**Scope strategy**: one indexed range scan against `user_preferences.digest_next_due_at` per run — no per-user polling. The index is **partial** (`WHERE digest_next_due_at IS NOT NULL` in `db/schema.rb`), so users without a digest schedule never appear in the scan at all; a user on `"instant"` frequency has `digest_next_due_at = nil` and is skipped by construction.

For each due user:

1. Captures `cycle_started_at` **before** selecting, then computes the recipient's still-unread notifications in the half-open window `[digest_last_sent_at, cycle_started_at)` (`read_at: nil`, excluding `security` types — security always delivers instantly)
2. If non-empty: dispatches `NotificationMailer.digest(user, ids)` — **ids, not records** — and stamps `digest_last_sent_at = cycle_started_at`. The half-open window means a notification arriving while the mail is built sits above the new watermark and lands in the next cycle, rather than falling below a watermark stamped after delivery and never being selected. The mailer re-queries those ids `where(read_at: nil)` at delivery time and sends nothing if they have all been read since — so reading an item in-app suppresses its digest line, and a row deleted by retention between enqueue and render cannot raise `DeserializationError` and dead-letter the whole digest.
3. Updates `digest_last_sent_at` + recomputes `digest_next_due_at` via `UserPreferences#reschedule_digest!`, which writes `NotificationPreferences#next_due_at` — the user's cadence (`daily` or `weekly`, stored in `notification_preferences`) in their own timezone (digest hour is hardcoded at 8 AM local)

If quiet hours block delivery at the digest time, the digest is held until the window closes.

**Cycle-boundary semantics**: dedupe between cycles is the half-open watermark, not a stamp on the notification. `cycle_started_at` is captured before the SELECT and becomes the next floor, so the windows tile exactly — no gap, no overlap. What suppresses a digest line is the recipient **reading** the item; the job marks nothing on the row itself. That is a deliberate change: `seen_at` was written only by this job, to itself, and read only by this job's own scope, so the digest deduped against its own bookkeeping and emailed people things they had already read. The accepted trade, stated: glancing at the list without opening an item does not suppress its digest line. If the downstream mail job fails after the watermark is stamped, those items do not re-enter a later digest — recovery is the in-app surface, which still shows them unread, plus the mail job's own retry policy.

### `NotificationCleanupJob`

Per-user retention enforcement. For every user:

1. `days = ApplicationNotifier.preferences_for(user).retention_days` — the single owner of the missing-row fallback, so a user with no preferences row is swept at the schema default carried by `UserPreferences.new` (90, matching `DEFAULT_RETENTION_DAYS`), and a pre-migration explicit null reads as `NEVER_CAP_DAYS` (365).
2. Cutoff = `(days + 2).days.ago` (2 days of slack against timezone drift; it only ever keeps a row longer).
3. Delete `Noticed::Notification` where `recipient_id = user.id` AND `read_at < cutoff` AND `read_at IS NOT NULL`.

**Unread is never deleted**, regardless of age: the retention clock starts at `read_at`, not `created_at`.

**No retention floor at this layer.** A security-category notification expires under the user's retention like any other row. The durable record of that event is its `ActivityLog` row, kept for at least `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR` (365 days) — see [Security event audit coverage](#security-event-audit-coverage).

**Fault isolation**: each user's sweep runs under its own `rescue StandardError`, reported through `Rails.error` with the user id. That isolates a per-user data fault (a malformed preferences row). It does not isolate a systemic one — SQLite's writer lock is global — so a cycle in which every attempted user failed re-raises and Solid Queue records a failure. There is no retry policy on this job and none from the queue: the recovery is tomorrow's fresh sweep, which re-attempts every user from scratch because nothing is stamped as done. A *partial* failure raises nothing, so the job logs a one-line summary naming how many users it swept, how many failed, and the last error class — without it the run reads as clean (#944).

**Batched deletion**: rows go out via `in_batches(of: 100, &:delete_all)` so the writer lock is released between rounds. Each yielded batch is derived from the scoped relation, so its DELETE still carries `read_at IS NOT NULL AND read_at < cutoff` and a row marked unread between the id SELECT and the DELETE is not deleted. That holds in both of `in_batches`' modes (`activerecord-8.1.3.1/lib/active_record/relation/batches.rb:440` for the id-list `rewhere`, `:457-458` for the range mode's `apply_finish_limit` on the same relation). A partial batch is re-entrant: the next run recomputes the cutoff.

`delete_all`, not `destroy_all`: `Noticed::Notification` has no callbacks worth running here. The one it has — noticed's counter cache on `noticed_events.notifications_count` — is bypassed by every deletion path in the app (this job, `Noticed::Event#has_many :notifications, dependent: :delete_all`, and `User#notifications, dependent: :delete_all`), so the counter is not a reliable signal; orphan-event pruning (#811) must use `NOT EXISTS`. `User#notifications, dependent: :delete_all` is also the *only* enforcement against orphaned notification rows: `noticed_notifications` carries no foreign key to users, so raw SQL or `User.delete_all` in a fork orphans them silently, and this job — which iterates `User.find_each` — never sees them again.

### `NotificationDispatchReconcileJob`

Re-enqueues `Noticed::EventJob` for every event whose `dispatched_at` is still NULL — see [Dispatch reliability](#dispatch-reliability) for why that column exists and what it deliberately does not cover. The scan is bounded at both ends, `created_at BETWEEN MAX_LOOKBACK.ago AND GRACE.ago`:

- **`GRACE` (5 minutes)** is well past any plausible enqueue latency, and short enough that a recovered notification is late rather than missing.
- **`MAX_LOOKBACK` (24 hours)** stops a row that can never be stamped — a deserialization discard, a fork's hand-written row — from being re-enqueued every cycle forever. It is also why the migration that added the column **backfills existing rows** with their own `created_at`: without that, the first sweep after deploy would have re-delivered the entire notification history, since nothing prunes events and `NotificationCleanupJob` deletes notification rows without touching `notifications_count`.

Events with `notifications_count == 0` are skipped: nobody for a re-enqueue to reach. The scan rides the partial index on `noticed_events (created_at) WHERE dispatched_at IS NULL`, which is empty in steady state.

**The sweep stamps each row itself, before enqueuing it.** Its enqueue is the one retry an event gets. Without that stamp, a delivery queue backed up past the 15-minute cadence would hand the next cycle the same unstamped row and fan a second copy of every email out to every recipient. Stamping *before* the enqueue rather than after settles the other direction too: if the enqueue raises, the row is already stamped and is never retried, and the per-row rescue reports it — a lost retry that is visible beats a duplicate fan-out that is not.

It runs on `default`, not `low`: `low` is chartered as work nobody is waiting on, and this re-delivers a notification a user is waiting on and already did not get. Same reasoning that keeps the two workspace notifier sweeps off `low`.

One constraint on forks: noticed's `deliver(..., wait:)` / `wait_until:` deliberately enqueues `EventJob` for later, which this sweep reads as a lost enqueue and re-delivers early. No dispatch in this app uses them; a fork that adds one must widen `GRACE` past its longest wait, or exclude that notifier from the scan.

Same fault posture as `NotificationCleanupJob`: each re-enqueue is rescued and reported through `Rails.error` with the event id, and a cycle in which *every* attempt failed re-raises so Solid Queue records a failure rather than logging a successful sweep. The recovered count is logged at the end of each cycle — a non-zero count means a delivery nearly went missing.

## Security event audit coverage

The three security notifiers above each pair with a row in `ActivityLog` — a separate table from `noticed_events`/`noticed_notifications`, with its own write guarantee and its own retention. `ActivityLog::SECURITY_ACTIONS` is the single membership set naming these events (`user.password_changed`, `user.password_removed`, `user.signed_in_new_device`, `user.passkey_added`, `user.passkey_removed`, `user.suspended`, `user.unsuspended`, `user.unlocked`, `operatorship.granted`, `operatorship.revoked`); `ActivityLogRetentionSweepJob` keys its retention exemption off `action` membership in that set, never off `visibility` — the `personal` visibility tier is a coincidence of who these rows are scoped to, not the test the sweep uses, so a fork adding an unrelated `personal`-visibility action doesn't silently inherit the security floor. Every row in that set is written through `ActivityLog.record_security_event!`, which owns the row shape and raises on an action outside the set — a drifted action literal fails loudly instead of writing a row that quietly misses the floor.

| Event | ActivityLog write | Guarantee | Other corroborating record |
|---|---|---|---|
| Password set / changed / removed | `User#audit_password_digest_change` (`after_update`) | **Strict** — same transaction as the `password_digest` write, no rescue; a failed audit row fails the credential write. Note the consequence when the credential change *is* a compromise response: the rollback also leaves the user's other sessions alive, since revocation commits with the rotation — they die when the rotation is retried successfully | — |
| Passkey added / removed | `WebauthnCredential#audit_added` (`after_create`) / `#discard!` | **Strict** — same transaction as the credential row; removal is a `Discardable` soft delete, not a destroy. Removal is deliberately *not* a callback: `discard!` claims the kept → discarded transition with a compare-and-swap and audits only if it won, because a callback cannot see another request's commit and two concurrent removals would each write a row. Enrollment stays a callback — the `external_id` unique index makes a duplicate create impossible | The soft-deleted `webauthn_credentials` row itself (`discarded_at` set, row not gone) |
| Sign-in from a new device | `Authenticatable#detect_and_record_new_device` | **Best-effort** — inside that method's own `rescue ActiveRecord::ActiveRecordError`; a failed audit write must never fail a sign-in | The `Session` row created moments earlier (the primary sign-in record; retained up to `absolute_timeout`, 90 days), and the user's `last_known_browsers` JSON column (a bounded LRU used only to decide "is this browser new?" — a fingerprint cache, not itself durable evidence) |
| Operator access granted / revoked | `Operatorship.grant!` / `#revoke!` | **Strict** — same transaction as the `operatorships` row; written at `admin` visibility with the granter or revoker as actor (none for a rake grant), so it appears in the operations feed rather than the subject's account card. No notifier pairs with it | The `operatorships` row itself (kept, or `discarded_at` set) |
| Account unlocked (operator) | `User::Password#unlock!` | **Strict** — same transaction as the `failed_login_attempts`/`locked_at` clear; written at `admin` visibility with the operator as actor (none for a rake unlock). No notifier pairs with it | The cleared `failed_login_attempts`/`locked_at` columns themselves |
| Account suspended / unsuspended | `User::Suspension#suspend!` / `#unsuspend!` | **Strict** — same transaction as the `suspended_at` write; written at `admin` visibility with the operator as actor (none for a rake suspend/unsuspend). No notifier pairs with it | The operations feed row; the destroyed `sessions` rows (suspend only) |

Passkey removal has no notifier of its own — only enrollment does, via `PasskeyAddedNotifier`; the ActivityLog row above is the only record that a passkey was removed.

Retention for this tier is governed by `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR` (365 days) rather than the job's 12-month `RETENTION_WINDOW`. **The two are numerically the same today** — `12.months.ago` and `365.days.ago` land on the same date in an ordinary year — so this is a *decoupling*, not an extension: security rows do not currently outlive ordinary ones. The floor only starts to bite if a fork shortens `RETENTION_WINDOW`, at which point credential-event history keeps its 365 days regardless. The sweep deletes security rows past the **earlier** of the two cutoffs, so the floor can only ever hold a row longer than the general window, never less (`12.months.ago` reaches one day further back than `365.days.ago` when the window spans a Feb 29 — without that guard the "floor" would invert for roughly one year in four). This ActivityLog row is the durable record of these events. The `noticed_notifications` row has no floor of its own (PR 5).

## Record preloads (index N+1 prevention)

The `/account/notifications` index eager-loads `includes(:recipient, event: :record)` for every row, but `includes` stops at the polymorphic `event.record` — it cannot reach the subtype-specific associations a notifier's `#message` traverses (a `ProjectMembership`'s `project`, an `Invitation`'s `invitable`). Each notifier therefore declares what its `#message` reads:

```ruby
class ProjectMembershipChangedNotifier < ApplicationNotifier
  record_preloads :project
end

class WorkspaceInvitationAcceptedNotifier < ApplicationNotifier
  # Nested form for polymorphic hops: only Project invitables have a
  # workspace; the pipeline skips classes lacking the association.
  record_preloads :accepted_by, invitable: :workspace
end
```

After pagination the controller calls `ApplicationNotifier.preload_records(@notifications)`, which groups the page by notifier type and batch-loads each type's declared associations — re-grouping by concrete record class at every level of a nested declaration, so polymorphic hops load only where they exist.

These traversals are deliberately **not** Bullet-safelisted: safelist entries are global (class + association, app-wide), so an entry "accepting" an N+1 on this page would also blind Bullet to genuine N+1s on every other surface. The guard is `spec/requests/settings/notifications_record_preloads_spec.rb`, which renders two notifications of every type in one request under Bullet's raise — a missing declaration fails as an N+1, a superfluous one as unused eager loading.

## Bullet safelists

`lib/bullet_safelists.rb` (shared by the development and test configs) keeps a small set of entries specific to this surface. They're not "ignored warnings" — each documents a constraint:

- **`SignInFromNewDeviceNotifier` unused_eager_loading on `:record`** — the index page eager-loads `event.record` for every row because every other notifier's `#message` interpolates `event.record.<attr>`. SignInFromNewDevice reads only `event.params`, so when it's the only subtype in a result the include looks wasted. The safelist documents the deliberate trade-off rather than dropping eager-load for all rows.

Two `:recipient` n_plus_one_query entries lived here until #1054 and are now gone. Their rationale was the `deliver_by :email` lambda's per-recipient `recipient_pref` check; #936 replaced that gate with one answered from the event's own permitted-id set, which reads no association. Nothing in `app/` or `lib/` reads `recipient` on a collection path any more — `recipient_pref` survives as an introspection shim with no caller outside specs — so the capacity entry was dead outright and the member-added one was held up only by spec-side reads, which now eager-load with `.includes(:recipient)`.

## Operational concerns

### Monitoring

Watch for:

- **`Rails.error` reports tagged `source: "NotificationBroadcaster.refresh_for"`** — cable adapter outages or partial-render errors. Notification persistence is unaffected, but the real-time UX degrades to "next page load."
- **Job failures** on `DigestMailerJob` and `NotificationCleanupJob` — queue assignment lives in `config/recurring.yml`. Neither declares `retry_on` and Solid Queue adds no policy of its own, so a failed run lands in `solid_queue_failed_executions` and stays there; the recovery is the next scheduled run, not a retry. Watch `NotificationCleanupJob`'s `swept N of M users` warning for partial failures, which never raise.
- **`noticed_events` growth rate** — `NotificationCleanupJob` prunes an event once it has no notifications left, in the same pass that deleted them. Pruning is **childless-only and never age-based**: deleting an event cascades to every recipient's row through the FK, so age is the one criterion that could take live notifications with it. Childlessness is decided by a subquery against `noticed_notifications`, never by `noticed_events.notifications_count`, which is deliberately stale (#811).

### Tuning

- **Retention** is per-user via `notification_preferences.retention_days` (choices in `NotificationPreferences::ALLOWED_RETENTION_DAYS`; absent-key and explicit-null defaults in `DEFAULT_RETENTION_DAYS` / `NEVER_CAP_DAYS`). The only retention floor is the audit sweep's `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR`.
- **Digest hour** is hardcoded at 8 AM local in `NotificationPreferences#digest_hour_local`. Per-user configuration was deliberately removed in the v2 redesign — IA simplification.
- **Idempotency window** is 1 minute (the `minute_bucket` divisor). Increasing it widens the dedup horizon. Cross-minute retries by design land in distinct buckets and both succeed.

### Adding a new notifier

1. Subclass `ApplicationNotifier` under `app/notifiers/`
2. Declare `category :name` (one of `security`, `account_access`, `workspace_activity`, `project_activity`, `billing`)
3. Declare `severity :level` (one of `:danger`, `:warning`, `:info`, `:success`) — drives the bell color; omitting it defaults to `:info`. Then add the notifier to the roster in `spec/notifiers/notifier_severity_assignments_spec.rb` — that spec fails until you do, so a forgotten `severity` cannot quietly ship as `:info`
4. Define `notification_methods do; def message; def url; end` (use `event.record.*` for context)
5. Add `deliver_by :email, ... if:` guards if you want email
6. Add I18n keys under `notifications.<notifier_snake_case>.message`
7. If `#message` traverses associations off `event.record`, declare them: `record_preloads :project` (nested form for polymorphic hops: `record_preloads invitable: :workspace`). Then add the notifier's delivery to the roster in `spec/requests/settings/notifications_record_preloads_spec.rb` — that spec fails until you do, and it is what proves the declaration right (missing → N+1, superfluous → unused eager loading)
8. Dispatch from a **model callback** when the notification is about a record changing — that is the seam every write path shares, so no caller can forget it. Move to a controller or PORO only when a callback would fire on writes the notification is not about: `WelcomeNotifier` is the standing example (`User` has `after_create :onboard_workspace`, so a callback would fire for every seeded and factory-built user, not just a real registration). Record the reason at the notifier when you take the exception
9. Dispatch as `NotifierClass.with(record: ...).deliver(recipient)` when the call site knows the recipient, or `.deliver(nil)` when the notifier declares a `recipients` block. The two are not interchangeable; see *In-app gating lives in `recipients`* above for why, and `spec/code_smells/notifier_recipients_block_dispatch_spec.rb` for the fence

The `category` + `severity` macros and the `with` parameter are enough to route the new notifier through the existing preference gates, bell-indicator severity selection, idempotency, broadcasts, retention, and digest pipeline. No controller or view changes needed.

One extra obligation if the notifier reaches an **invitee** rather than a workspace member: re-check `Invitation#deliverable?` at the notifier's delivery gate — the last hop it controls — and add the site to the delivery-site roster in [Security](/docs/developer/security#invitation-blocks-decline-and-block). A preference gate is not a deliverability gate.

## Related

- **End-user instructions** for the same feature — switch to **User Guide** in the sidebar to view the user-facing companion to this doc
- **Architecture overview** — [Architecture](/docs/developer/architecture)
- **Email flows** — [Email Flows](/docs/user/emails)
