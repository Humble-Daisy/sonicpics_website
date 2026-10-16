---
title: Testing
description: Suite architecture, testing conventions, and the guards that keep the suite honest
keywords: testing rspec parallel sharding coverage code smells i18n bullet cuprite ferrum cdp stimulus csp webauthn sqlite lock flaky system specs
---

# Testing

How the test suite is put together: the parallel runner and CI sharding, the convention-enforcing guard specs, the system-spec infrastructure, and the fail-fast guards that turn confusing whole-suite failures into one actionable message.

## Suite architecture

### Two ways to run the suite

- `bundle exec rspec` is the single-process reference path — always correct, just slow.
- `bin/parallel-rspec` is the full-suite path: it runs the suite across all cores via `parallel_tests`, with two integrity gates layered on top of pass/fail. Before the run it reloads the schema into every worker database and seeds it, so the pre-push suite and CI's shards both start from the same four global roles; a bare `rspec` does no seeding of its own.

The two gates exist because a parallel splitter can silently drop work:

1. **Example-count parity.** A `--dry-run` enumeration fixes the expected example count before the run, and the per-worker counts must sum to exactly that number. The enumeration costs about 50 seconds per run — a deliberate price (#496) for "green means everything ran". It exists because the splitter really has dropped files; don't move it to a schedule or hide it behind a cache.
2. **Merged coverage floor.** Each worker sees only ~1/N of the suite, so workers skip the minimum-coverage check; `SimpleCov.collate` enforces the floor on the merged result instead.

The floor is a whole-suite number everywhere. A bare `bundle exec rspec` is held to it; a focused run (`bundle exec rspec spec/models/user_spec.rb`) is measured but not held to it, because `spec/rails_helper.rb` asks `CoverageConfig.floor_for` whether the files RSpec was given are the whole suite. `SKIP_COVERAGE=1` turns instrumentation off altogether, which is faster for a tight loop but is not needed to make a focused run pass.

Worker count comes from `PARALLEL_TEST_PROCESSORS` or the machine's core count.

### CI sharding

CI splits the suite across a shard matrix (#495, PR #615) — 8 shards of 4 workers by default, the free public-runner shape. A fork sets the `CI_SHARDS` and `CI_WORKERS` repository variables in its Actions settings to change that without editing a tracked file; private repositories are billed per job, rounded up to the minute, so fewer, longer shards cost less there. With `CI_SHARD_INDEX` and `CI_SHARD_TOTAL` set, `bin/parallel-rspec` takes only its shard's slice of the spec files — greedy-packed by recorded per-file runtimes, with file size as the fallback weight — and skips the merged-coverage floor (each shard sees only a fraction of the suite; the `coverage_merge` CI job collates every shard's resultset and enforces the floor there). Example-count parity still runs per shard against the shard's own enumeration, and each shard records its file list so CI can assert the union of shards equals the full spec set — the shard splitter gets the same distrust as the worker splitter.

### The runtime log lifecycle

`bin/parallel-rspec` writes `tmp/parallel_runtime_rspec.log` — per-file spec timings. `parallel_tests` reads it on the *next* run to split work by measured time instead of file size, which evens out the slowest worker. That only helps if the log survives between CI runs, so it is cached (#488), and since sharding the lifecycle spans three jobs:

- `split_seed` snapshots one **frozen** copy of the log, downloaded by every shard — the cross-shard split must be computed from identical input or shards overlap and leave holes.
- `test_shard` restores the live log separately to seed *in-shard* worker balancing.
- `coverage_merge` reassembles every shard's partial log and saves the cache for the next run.

A cache miss is harmless: the split falls back to file size — still correct, just less balanced.

## Conventions and guards

#### What a `SEED=` replay does and does not reproduce

`SEED=<n> bin/parallel-rspec` replays a failing interleaving: every worker runs
the same ordering seed, and — because the live runtime log changes between runs
— an explicit `SEED` also pins worker grouping to file size and stands the
runtime logger down, so a replay is deterministic from the working tree alone
and never overwrites the balance data. What it does **not** reproduce is
Faker-derived *data* from a run under a different file-to-worker mapping: each
worker's Faker stream position depends on which files it ran and in what order.
A clean replay therefore rules out an ordering flake, not a data-dependent one
— before concluding "cannot reproduce", check whether the failing assertion
involves Faker-generated values (see #856-class collisions).

### The code-smells suite

`spec/code_smells/` holds specs that enforce project conventions structurally rather than by review. Examples: `mutating_actions_are_authorized_spec.rb` fails if a POST/PATCH/PUT/DELETE action neither calls `authorize` nor sits on the reviewed allow-list, and `no_unscoped_tenant_loads_spec.rb` fails on unscoped tenant finders in controllers (see [Extending](/docs/developer/extending)).

The largest member is `spec/code_smells/template_invariants_spec.rb`. ModelRails is a template meant to be forked, so every default it ships propagates into every downstream fork; this spec asserts the structural invariants that came out of an 8-reviewer panel review on 2026-05-18. Each one catches a class of subtle misconfiguration that would otherwise propagate silently — Ruby-version drift across `.tool-versions`, `Gemfile`, `Gemfile.lock`, and the `Dockerfile`; test gems leaking into the production image; Dockerfile layer-cache invalidation from COPY ordering; dev/prod base-image divergence; missing onboarding signals; unused free performance settings; every workflow `uses:` SHA-pinned with its `# <tag>` trailer (the action-pin invariant — a fork's own unpinned ref fails the suite too) — plus invariants added since, such as the vulnerability-scan rules below.

One of those is worth understanding when a CI change makes it fire: the container vulnerability scan must **never** reuse the Docker layer cache (#536). GitHub Actions cache scoping makes a branch read its *own* cache scope first, so a PR replays its own stale apt layer and never sees the fix main already picked up — stale-package CVE findings then look identical to real ones. Rebuilding costs about 45 seconds per run, which is cheap for a red that always means what it says.

### Destroy requests name their target

`spec/code_smells/destroy_requests_name_their_target_spec.rb` exists because of #1402. The identity picker's **Remove photo** button sent `DELETE` to whatever URL it was given, a workspace passed the URL where its logo *saves*, and that URL's DELETE was `workspaces#destroy`. One click discarded the workspace. Nothing about the partial looked wrong on its own; the bad value arrived one partial up, as an ordinary route helper.

So the guard reads every request a template can make (`button_to`, `link_to`, `form_with`, `form_tag`, under `app/views` and `app/components`) and, when the URL or the method is one of the template's declared locals, follows it to every `render` that passes it in, then up again until it reaches the template that names a real route helper. Each DELETE that comes out of that walk is checked against the route table:

- it must land on a named route that actually has a DELETE action;
- if that action soft-deletes (its controller's `destroy` calls `discard!`, a set derived from the controllers rather than listed by hand), the walk must pass through `shared/confirm_dialog`.

When it fires, the message names the whole render chain, outermost template first, so the place to look is usually the first template in it: that is where the URL was chosen. Point the control at the child resource it names, or put the destroy behind the confirm dialog. The guard reads template text, so it has blind spots, and it prints them whenever a rule fails: collection renders (`render partial:`), URLs built in Ruby, hand-written HTML method overrides, and partials nothing renders. Its negative control replays #1402 on the Profile page and must keep failing.

### The two i18n gates

Two complementary gates cover missing translations, and it is worth being precise about which covers what:

- **`config.i18n.raise_on_missing_translations`** (in `config/environments/test.rb`) catches a missing key at runtime — but only on a code path some spec actually walks, and only when the call site has no inline `default:` to swallow it. Since `available_locales` is pinned to `[:en]`, this raise only ever exercises the base locale.
- **`spec/i18n_spec.rb`** (backed by i18n-tasks) is the static counterpart: it catches missing keys repo-wide without executing anything, including cross-locale gaps once a fork adds a locale. It also fails on inconsistent interpolations and on **unused keys** (#522 — 120 orphans were cleared when that gate landed). Delete unused keys, or add them to `ignore_unused` in `config/i18n-tasks.yml` with a reason when the consumer is dynamic or lives in a scanner-excluded path.

`config.i18n.fallbacks` mirrors production so a lookup reaching a non-base locale terminates at `:en` rather than dying — a key missing from `:en` still raises, which is the point.

### Bullet safelists live in one file

Bullet raises on N+1 queries in test and alerts in development. Its safelists — intentional preload and delivery-layer trade-offs that hold in both environments, since the app code is identical — are centralized in `lib/bullet_safelists.rb` rather than duplicated per environment file. They drifted once: `development.rb` carried only two entries while `test.rb` had the full set, so false positives fired in dev but never in test, invisible to the suite. One source removes that whole class of drift. Each environment file keeps its own enable/display/raise configuration and calls `BulletSafelists.apply` after `Bullet.enable = true`.

Every entry is an unused-eager-loading safelist: a preload kept on purpose because the rows that need it would otherwise N+1, accepted as a false positive on the rows that don't.

| Entry | Why the preload goes unused, and why it stays |
| ----- | --------------------------------------------- |
| `ActiveStorage::Attachment :record` | A framework false positive. ActiveStorage's bulk touch (`touch_attachment_records`) includes `:record` for its SQL but never reads the objects in Ruby. |
| `SignInFromNewDeviceNotifier :record` | The notifications index includes `event: :record` because nearly every notifier's `#message` reads `event.record`. The new-device notifier reads only `event.params`, so a page holding only those rows leaves the include unused. |
| `Invitation :role` | The members index preloads invitation roles for its combined table. Invitations sort to the front, so page 2 onward, or a filter matching no invitations, renders none. The #124/#125 boundary specs exercise exactly those slices. |
| `Membership :user`, `Membership :role`, `User :avatar_attachment` | The workspace sidebar switcher preloads `memberships: [:role, { user: :avatar_attachment }]` so `workspace_icon_for` can fall back to the owner's avatar. The fallback is skipped when a workspace has its own logo or the sidebar posture is `:none`, and `Workspace#owners` short-circuits on loaded memberships on the workspaces index. Every leg is safelisted, deliberately pessimistic. |
| `Membership :workspace` | `WorkspacesController#index` queries memberships, joins and preloads the workspace to sort by `memberships.last_accessed_at`. Bullet reads the preload as redundant against the join, but the view needs it for each row's name and icon. |

The N+1 safelist is empty on purpose (#1054). A Bullet safelist is global, keyed by class and association across the whole app, so an entry that accepts an N+1 on one page would also hide a real one everywhere else. The notifications index's second-level traversals off the polymorphic `event.record` go through `ApplicationNotifier.preload_records` instead, guarded by `spec/requests/settings/notifications_record_preloads_spec.rb`.

### Rake task specs load once

A spec that invokes a rake task calls `RakeTasks.load_once`
(`spec/support/rake_tasks.rb`), not `Rails.application.load_tasks` directly:
loading twice appends a second copy of every task's body, so an aborting
task raises `SystemExit` mid-example on its second pass — and RSpec still
prints "0 failures" for the run it just cut short. The exit code is the
verdict, not the summary line.

### Reviewed lists behind the guards

Two support files hold reviewed lists that code-smell specs enumerate
against rather than re-deriving by pattern-matching:

- `spec/support/security_event_writers.rb` — `SecurityEventWriters::ALLOWED`,
  the files permitted to write `ActivityLog` rows directly outside
  `Trackable` and `record_security_event!`. Shared by the guard that proves
  no other file bypasses the writer and the one that derives which literal
  actions those files may write.
- `spec/support/source_scanning.rb` — `without_comments` and friends, the
  shared source-text scanning helpers behind the code-smell specs that read
  `app/` as text rather than through a runtime representation.

## System-spec infrastructure

System specs run on Capybara + Cuprite, a pure-Ruby CDP driver (the suite migrated off Playwright in #497 — no Node dependency). The support files below make that stack reliable.

### Waiting in system specs

A system spec waits for observable state, never for a clock. `visit` already waits for every Stimulus controller to connect (the readiness gate below), and Capybara's matchers retry on their own budget (`Capybara.default_max_wait_time`, longer on CI), so `expect(page).to have_css(...)` is the wait. A bare `sleep N` before an assertion passes green under load with the state you wanted still on its way; it is what the `ModelRails/NoSleepInSystemSpecs` cop (`lib/rubocop`) fails on commit. Two shapes look like `sleep` and are not the banned one:

- **A bounded poll**, for state Capybara cannot see — a preference row, a `localStorage` key, a computed style: `Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until user.preferences.reload.timezone.present? }`. The `sleep` is the tick; the condition and the budget are the wait. A `sleep` inside a `loop`, `until`, `while`, or `times` block reads the same way.
- **A named negative wait**, for proving that a request did *not* arrive, which no condition can express: `sleep 0.3 # post-connect round-trip margin for a wrongful clobber`. It is allowed only after a condition-based wait, and the inline comment naming what it waits out is what the cop reads; without it the line is a bare sleep.

### CDP helpers

`spec/support/cdp_helpers.rb` wraps the Ferrum/CDP operations the specs need — Cuprite exposes the underlying `Ferrum::Browser` at `page.driver.browser`. The helpers came out of the Playwright→Ferrum migration (#497): `cdp_evaluate` / `cdp_evaluate_async` / `cdp_execute` for JS, `cdp_add_init_script` (call before visiting), `cdp_press`, `cdp_click_at`, `cdp_clear_cookies`, `cdp_resize`, `cdp_emulate_reduced_motion`, `cdp_intercept`, and raw `cdp_command` — each documented at its definition. Two gotchas the helpers encode: Ferrum's `evaluate` wraps source in a returning function, which breaks UMD bundles like axe-core (`cdp_execute` runs the raw statement instead), and network interception has no per-route handler — every intercepted request **must** call `.continue`, `.abort`, or `.respond`, or Ferrum leaves it hanging.

### Stimulus readiness gate

The importmap module fetch and Stimulus boot lag behind page load, so anything that lands before a controller connects reads a page the controller has not touched yet — a dispatched event is silently dropped, and an element still carries the class the server rendered. That is harmless while a warm spec always runs first, but random spec ordering can make any spec the *first* to run against a cold module cache — an intermittent, load-dependent failure.

Rather than sprinkle waits across specs, `spec/support/stimulus_ready.rb` waits once, centrally: **after every system-spec `visit`**, it blocks until every `data-controller` element on the page has its controllers connected. `spec/system/stimulus_ready_gate_spec.rb` pins that behavior.

The gate used to be an allow-list of two paths — the Lookbook component previews (`/rails/view_components/`) and the form-drafts harness (`/draft_harness`, #525) — each added after a specific flake. That left the other ~536 `visit` calls ungated and #837 recurred a third time on one of them, so the gate was widened rather than annotated call site by call site.

Two properties matter when reading it:

- **It raises, it does not proceed.** A barrier that times out silently is indistinguishable from one that succeeded. The message names the identifiers still unconnected, which is what separates "module still fetching" from "identifier will never register" (a typo'd `data-controller`).
- **A page with no controllers is ready immediately**, even with no `window.Stimulus` — a redirect target or a plain error page must not spend the budget and then raise. A still-parsing document is *not* treated that way: an empty match there means "too early", not "nothing to wait for".

The race does not reproduce at ordinary local load, which is why #837 recurred three times before it was closed properly. To open the window deliberately, cold the module cache and throttle the network — the lag is the importmap module fetch, not CPU, so `Emulation.setCPUThrottlingRate` will not do it:

```ruby
cdp_command("Network.enable")
cdp_command("Network.clearBrowserCache")
cdp_command("Network.emulateNetworkConditions",
            offline: false, latency: 250, downloadThroughput: 100_000, uploadThroughput: 100_000)
page.visit(root_path)          # page.visit bypasses the gate; `visit` does not
all_stimulus_controllers_connected?   # => false, the window an assertion can land in
```

Those numbers are machine-specific: too gentle and the page is already connected on load, too harsh and the barrier legitimately exhausts its budget and raises. Tune until `at_load` is false and the barrier still succeeds.

### CSP violation capture

The Content-Security-Policy is enforced in test exactly as in dev and prod, and `spec/support/csp_violation_capture.rb` makes the browser tattle on violations. The source-level scan (`spec/code_smells/no_inline_event_handlers_spec.rb`) catches inline handlers, but the suite once shipped two CSP bugs it was structurally blind to: a blank-nonce generator that emitted an invalid `'nonce-'` and silently blocked every inline script for first-time visitors (#499), and an initializer override that un-enforced CSP in test (#500 follow-up). CDP-driven specs dispatch events at protocol level, so they never needed the blocked scripts — but the browser knows, and fires `securitypolicyviolation` for every block.

The support file installs an init script on each example's fresh page — install is page-scoped, and the after-example session reset disposes the page along with its init scripts, so a per-process install would cover only the first example a worker runs (#848; `spec/system/csp_violation_capture_spec.rb` proves the listener survives that reset). The script accumulates violations in `sessionStorage`, so same-tab navigations within an example don't lose them. An after-hook reads *and clears* the list — nothing bleeds across examples — and fails any example that produced a violation. The `ALLOWED_VIOLATIONS` list is empty by design; every future entry needs a written reason.

### Triage note: two cross-cutting hooks can fail any system example

Every system example runs two after-hooks that can fail it for reasons unrelated to its own assertions: the WCAG 2.2 AAA axe audit (both themes, `spec/support/axe_accessibility.rb`) and the CSP-violation gate above. A failure raised inside an `after` hook is **reported against the example**, so an axe or CSP finding reads as a spec-body failure. When triaging a system-spec failure — especially an intermittent one — rule these out first: axe failures name the rule and theme (`[DARK] color-contrast: …`), CSP failures name the blocked directive. Both audit the example's *end* state, which may not be the state the example's own assertions ran against (#855).

The audits are memoized per example on page state + options, so an example that already ran `axe_clean_in_both_themes?` on its final state pays nothing extra in the hook — the memo never skips an audit of state nothing has covered (`spec/system/axe_audit_memo_spec.rb` pins both properties).

### WebAuthn virtual authenticator

`spec/support/webauthn_virtual_authenticator.rb` provides `with_virtual_authenticator { ... }`, which enables CDP's virtual authenticator (ctap2/internal, resident-key, `automaticPresenceSimulation: true`) so a system spec can drive real `navigator.credentials.create`/`get` calls with every gesture auto-approved.

The subtle part is **origin alignment**: the WebAuthn RP origin from the initializer is `http://localhost`, but Capybara binds its test server to `127.0.0.1:<dynamic port>` — and WebAuthn treats `127.0.0.1` and `localhost` as *different* origins. The helper temporarily sets `Capybara.app_host` to `http://localhost:<port>` so the browser's origin matches, and extends `WebAuthn.configuration.allowed_origins` to that exact URL (the port matters for the gem's origin check). Both are restored after the block.

## Troubleshooting the suite

### "Another process is holding the test database"

Each test database is one SQLite file, and `config/database.yml` installs a 5-second busy handler (#304). Two runners on the same test database therefore do not fail fast — every contended statement waits out the handler before raising, so the suite crawls and sheds failures across unrelated files, none of which name the cause. (Observed once in a fork: a 12-minute suite took 85 minutes and produced 30+ phantom failures.) `spec/support/test_database_lock_guard.rb` refuses to start a run into an already-locked database: a `before(:suite)` `lsof` check names the holding PIDs and the fix.

Two things to know when it fires:

- Stop the other run by **process group**, not by name — the guard's message prints the exact `kill -- -<pgid>` command. `pkill -f "bundle exec rspec"` is the trap: it matches the shell wrapper and orphans the child, which keeps the WAL lock, after which every run fails on the first `create(...)`.
- Parallel workers each get their own database file, but `TEST_ENV_NUMBER` is empty for worker 1 — so a parallel run and a plain `bundle exec rspec` genuinely do collide on `storage/test.sqlite3`.

The guard lives in the spec boot path rather than a wrapper script on purpose: a guard you have to remember to invoke protects nobody, and this way it covers the plain runner, every parallel worker, agent invocations, and IDE runners alike.

### "Compiled Tailwind stylesheet missing"

System specs load the compiled Tailwind stylesheet from the test server. When it is missing, axe reports contrast violations on every page and interaction specs fail on collapsed layout — 132 failures that name neither Tailwind nor assets. `spec/support/compiled_assets_guard.rb` checks for `app/assets/builds/tailwind.css` before each system spec and fails with the actual fix: `bin/rails tailwindcss:build`.

The hole is easy to fall into: `assets:clobber` (which `bin/setup` runs deliberately) also deletes the compiled stylesheet, and the tailwindcss-rails safety net that rebuilds it hooks `test:prepare` — the Minitest path, which `bundle exec rspec` never invokes. The guard is read-only by design: building the CSS from inside the suite would race, since `bin/parallel-rspec` boots one RSpec process per core.

## Next steps

- **[Accessibility](/docs/developer/accessibility)** — how the axe-core AAA checks fit into system specs.
- **[Architecture](/docs/developer/architecture)** — the tenancy and authorization invariants many of the guard specs enforce.
- **[Getting started](/docs/developer/getting-started)** — environment setup, including the pieces (`bin/setup`, compiled assets) the guards above assume.
