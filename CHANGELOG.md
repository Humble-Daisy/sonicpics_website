# Changelog

All notable changes to ModelRails are documented here, organized by phase.

## [Unreleased]

### Added

- A project resource's page offers **Delete**, behind a confirmation, to its author, the project's creator and the workspace's owners; its notice now says the resource was deleted rather than archived.
- A code-smell spec follows every DELETE in the templates through the partials that pass its URL, and fails when one lands on a route with no destroy, or discards a record without going through the confirm dialog — so a control can no longer point Remove at a parent record's destroy (#1402).
- The Herb check also covers the 289 Lookbook previews, the Turbo Stream templates (compiled through Herb although Rails still uses Erubi for that format) and the static pages in `public/`, each with a floor.
- A code-smell spec compiles every HTML+ERB template through Herb on every pull request, so a mismatched tag or ERB output in attribute position fails the suite; the one gem template that fails today (#1341) is a reviewed exception the spec drops once it compiles.
- `bin/rails action_text:clear_filename_alts` (with `DRY_RUN=1`) removes the file-name alt text Lexxy 0.9 wrote on uploaded images, so they open the ALT dialog empty; run it once on a deployment with pre-1.0 content. Lexxy's attachment toolbar and ALT-dialog buttons meet the 44px target floor, held by an AAA system spec. (#1339)
- The header bar paints from a family of chrome tokens (`--color-chrome`, `--color-on-chrome`, `--color-chrome-focus`, …) that default to today's look, so a fork brands the bar from `_brand.css` without editing the header; a code-smell spec holds a branded chrome to AAA, and the account and mobile menus keep their own surface.
- The UI patterns doc carries recipes for the pages the template repeats, each naming its parts and a view to copy from, and a docs spec holds each recipe to the views it names (#1308).
- Docs that explain sign-up list the code behind it under `code: signup:` in their front matter, and a docs spec fails when a listed path no longer exists.
- A code-smell guard refuses a spec helper copied into a second spec file or shadowing one in `spec/support` (#1273).
- `bin/rails db:schema:regenerate` rebuilds `db/schema.rb` from `db/migrate` alone, and a pre-commit check refuses a `db/schema.rb` the migrations do not produce.
- `CHANGELOG.md` merges by union, so parallel pull requests that each add a line no longer conflict on it.
- A docs spec fails when a tracked developer page cites a repo path that does not exist; absent-by-design citations carry a reason.
- Specs pin the activity feed's actor snapshot, its legacy-row preloader, and the partial's snapshot render (#1251).
- The developer notifications doc carries the write-time coalescing recipe, which until now lived only in design notes (#806).
- The comment-block gate also runs in CI over a pull request's diff (`bin/comment-block-check --range`), so a skipped hook or a fork without Lefthook still meets it.
- Pre-commit check refuses comment blocks over two lines that a commit touches (`bin/comment-block-check`).
- Blocked senders page in account settings; unblocking is self-serve (#812).
- Resource forms recover unsaved drafts, including the rich-text body (#479).

### Changed

- A pull request that changes a build input builds the production image once, in `image_scan`'s cold build, instead of twice; `docker_build` runs on every push to `main` and on pull requests only to test its own workflow.
- Bullet 8.3.0 supports Active Record 8.2, so it loads like any other gem and the Rails-main load shim is gone (#1337, #1409).
- Dependabot groups gem updates into one weekly pull request, as it already does for actions, so a week's bumps cost forks one CI run instead of one per gem (#1406).
- CI's shard count and in-shard worker count come from the `CI_SHARDS` and `CI_WORKERS` repository variables (default 8 and 4), so a fork on a smaller or billed runner sets its own shape in Actions settings instead of editing the workflow (#1407).
- The production image build is its own workflow: a pull request runs it only when a build input changes (`Dockerfile`, `.dockerignore`, `Gemfile`, `Gemfile.lock`, `.tool-versions`, `bin/docker-entrypoint`) and every push to `main` runs it unfiltered; the pre-push hook runs the same build locally through `bin/docker-build-check` on the same inputs (#1405).
- The timezone beacon renders only while a user's timezone is unset, so a Turbo visit no longer sends a PATCH; the passkey, identity-picker and beacon requests stop attaching an authenticity token that header-only CSRF never reads (#1351).
- The sidebar spec moves the pointer off the rail before it checks the tooltip bubble is hidden, so a pointer left over the rail by an earlier spec can no longer hover the bubble in and fail it.
- The identity picker specs wait for the hub to render, not only to load, so a late render can no longer save the default hue in place of the dragged one (#1344).
- Four guards can now fail for the right reason: the flash guard reads every controller line that names a flash and proves itself on a planted controller, three notifier specs drain both Noticed stages before asserting no mail, the CVE-2026-66066 check makes libvips refuse an untrusted file, and Permissions-Policy is asserted by value (#1350).
- **Fork-facing:** password sign-in is opt-in. `AUTH_PASSWORDS` (read into `config.x.authentication.passwords`) defaults to `disabled`, which draws no password sign-in, password reset or `/settings/password` routes, offers no password at the lookup step or at reauthentication, and sends a leftover `set_password` link to the home page. **If your users sign in with passwords, set `AUTH_PASSWORDS=enabled` before syncing.** Without it they keep their account and sign in with a magic link or passkey. The test environment enables passwords; `spec/requests/passwords_opt_in_spec.rb` runs the default.
- **Fork-facing:** a failed password sign-in re-renders the password step (422) with a focused error summary and the address kept, instead of redirecting to the lookup step; an unknown address, a blank password and a locked account get the identical response, and a blank password no longer counts toward the lock. A lock is announced to the holder by email (`PasswordLockedNotifier`), never on the page. The lookup step answers every address alike: the password form is inline for everyone (the `GET /session/password/new` route and its `email_address` query are gone), and with signups closed an unknown address sees the same "check your email" page and is sent nothing, instead of the invitation-only notice. Specs that asserted the old redirect, the closed page or the password route need updating.
- The production preflight refuses a blank `SMTP_USERNAME` or `SMTP_PASSWORD`, so a relay that needs no login must opt out of the preflight; `MAIL_DELIVERY` is gone, since SMTP is the only transport (#1349).
- An image without a description renders `alt=""` and leaves its caption to name the file, instead of announcing the file name twice; a keyboard-only spec covers the ALT dialog through Alt+F10 (#1347).
- The test environment shuffles the rows of every unordered SELECT (`shuffle_unordered_selects`), so a spec that leans on SQLite's incidental order fails deterministically.
- `load_defaults 8.2`: HTML templates compile through Herb, writes are verified by `Sec-Fetch-Site` instead of an authenticity token, jobs enqueue after the transaction commits, attachments are analyzed before validation, and `X-XSS-Protection` is no longer sent. `development.rb` keeps only its local decisions (#625), and `SOLID_QUEUE_IN_PUMA=false` or `0` now turns the in-Puma supervisor off.
- Rails runs from a pinned commit of Rails main (8.2.0.alpha), with `load_defaults 8.1` kept: Action Text attachments carry alternative text and Lexxy's ALT button is on. `rspec-rails` is pinned to a main commit (#1338), Bullet loads through a patch until it supports Active Record 8.2 (#1337), and Dependabot ignores exactly the git-pinned gems.
- The Rails security floor and the `ModelRails/StackFloor` cop accept a later Rails minor or a git pin to a full commit; the CVE-2026-66066 check now reads the fix from the locked Active Storage source.
- The `modelrails_ui` pin moves to `v0.24.0`: every doc a vendored component's header points at now says when to use the component, and a guard fails the suite on a pin whose docs do not. The release's Reduce Motion fix is not yet carried into the vendored copies.
- The comment-block gate skips Lookbook preview classes, whose comments are the notes Lookbook renders (#1313).
- **Rich text runs on Lexxy 1.0.** The editor now keeps its textbox's ARIA in step when the field's attributes change after load, and supports `setCustomValidity`; the existing aria contract (error and description reaching the textbox a screen reader reads) is pinned in `spec/system/lexxy_editor_aria_spec.rb`. Link dialogs trap Tab, and Escape on a closed toolbar menu no longer throws focus into the document. Lexxy 1.0 also authors image alt text, but only when Action Text has an `alt` attachment attribute, which arrives in Rails 8.2; a request-spec tripwire fails the day it switches on. Newly uploaded images carry an empty alt inside the editor until then (the rendered page still falls back to the filename).
- Rails 8.1.4 and a bundle update: `db/schema.rb` lists columns in definition order again, and the activity feed passes Pagy's `client_limit` instead of the deprecated `max_limit`. Tailwind 4.3.3's default sans stack now names Roboto, Noto Sans and Arial before the generic fallback, so non-Apple platforms may render a different face.
- Notifier specs share one `drain_noticed_jobs` and `notifier_events`, and a stale `hard_delete` workaround becomes a plain `destroy!` (#1273).
- System specs share one `expect_aaa_in_both_themes`, `focused_text`, and `dismiss_cookie_banner`, and use `cdp_press` for keys, instead of per-file copies (#1273).
- The member-removed notifier's category, copy and link reasoning moves into the notifications doc; the notifier keeps two-line gists.
- Each Bullet safelist entry's reason moves from `lib/bullet_safelists.rb` into a table in the testing doc; the file keeps a one-line gist per entry.
- `Trackable`'s 36-line header becomes a two-line gist; its writer-by-tier list moves to the architecture doc, corrected (WebAuthn removal is audited inside `discard!`).
- The workspace model's long comments become gists with pointers; why `discard!` cascades in its own transaction now lives in the architecture doc.
- The flash guard keeps no list of exceptions: every flash a controller sets is asserted by its message (#526).
- Account settings' seven remaining flashes are asserted by their exact message, including the reauthentication rate limit, which had no example (#526).
- Workspace and project-tool flashes are asserted by their exact message, so joining and "already a member" no longer read the same to the specs (#526).
- Sign-in and account-linking flashes are asserted by their exact message; eleven entries leave the #526 list, 25 remain.
- Onboarding's five flashes are asserted by their exact message, so sending invites and skipping no longer read the same to the specs (#526).
- An rspec run that selects no examples fails, and `bin/comment-block-check` called with no paths refuses rather than passing.
- Two redundant indexes on `noticed_notifications` are dropped; the composite recipient index serves the unread filter and the inbox, and the plans are pinned (#1199).
- Ruby 4.0.7 and Bundler 4.0.20; the resolv and net-imap `.trivyignore` exceptions retire because 4.0.7 ships the fixed gems, and json's is re-dated.
- Comments added in app/ and lib/ since the 2026-09-21 plan cut to at most two lines each (658 lines to 125).
- Comments added in config/ and db/ cut to at most two lines, and this run's changelog entries to one line each.
- Comments added in spec/ since the plan cut to at most two lines each (1,149 lines to 259).
- Activity log rows snapshot the actor's name; `actor_id` no longer carries a foreign key (#1122).
- Notification broadcast cost measured and documented next to the code rather than debounced (#1200).
- Theme resolution defined once, in the pre-paint script (#624).
- Operations users page is a paginated index (#1135).

### Fixed

- A password lock emails the holder (`NotificationMailer#password_locked`), as the security guide promised: `PasswordLockedNotifier` declared no email delivery, and security notifications never reach the digest, so a signed-out holder learned nothing. The notifications guide lists the notifier once, not twice.
- `bin/rails action_text:clear_filename_alts` reloads each rich text under its write lock before cleaning it, so an edit saved while the task runs is no longer overwritten by the copy the task loaded earlier.
- Removing an avatar or workspace logo, or switching it away from an upload, purges the two image files only after the save succeeds; a failed save (an invalid stored colour, say) used to delete both files and still report the old upload source.
- The getting-started guide and `lefthook.yml` no longer advise skipping the hooks: a failing check is run on its own and fixed, since CI repeats every check anyway. `lefthook.yml` drops seven `skip_empty` settings that lefthook 2 ignores, so `lefthook validate` passes.
- The README and the getting-started gate tables describe the pre-push hook's eight checks and when the image build runs; the workspaces guide names the Profile and logo routes instead of a `/branding` route that no longer exists.
- **Remove photo on a workspace's logo removes the logo, not the workspace.** It sent `DELETE` to the workspace itself, which soft-deleted it; it now targets a logo endpoint that resets the logo to initials (#1402, #1412).
- `bin/parallel-rspec` reloads the schema and seeds every worker database before the suite, so a pre-push run starts from the same global roles CI does instead of an empty table; CI's shards no longer prepare databases in a separate step (#1401).
- Under Reduce Motion the sidebar no longer animates its width when it collapses (its labels still fade), and the rich-text editor's block caret stops blinking; the motion guard now reads `transition-[…]` lists (#1350).
- A mail send that could not reach the SMTP server (connect timeout, refused connection, busy reply) retries for about seven minutes instead of losing the sign-in link, and `bin/deploy-guide` names the SMTP settings (#1349).
- The rich-text editor takes a workspace's interactive colour (links, selection, the ALT dialog's Save) instead of the default brand blue, and the ALT dialog has a visible edge in dark mode with an outlined Cancel (#1348).
- A code block in the rich-text editor highlights its syntax at AAA in both themes: Lexxy's code colours now use the app's syntax tokens and code ground (keywords, strings and comments failed even AA in light mode), and the code-language picker meets the 44px target floor. A system spec holds both. (#1346)
- The signed-out Sign in link on the header bar paints from the chrome tokens, so it stays readable on a branded bar (1.45:1 before, on a dark brand); a signed-out example now holds the branded header to AAA.
- A fork's chrome tokens in `_brand.css` reach the header: the defaults sit in a zero-specificity `:where(:root)` block, since `_brand.css` loads before `_semantic.css` and a `:root` default outranked it. A system spec now brands the bar from a stylesheet loaded ahead of the app's.
- Production mail leaves over SMTP configured from the environment instead of Rails' `localhost:25` default; the boot guard refuses a deployment with no mail server, a failed delivery fails its job, and the deployment doc walks Postmark through with SES over SMTP as the second recipe (#1318).
- Reduce Motion reaches the components: every moving utility in the vendored UI components, three views, two previews and the select's picker arrow now honors `prefers-reduced-motion`, and a code-smell guard ported from modelrails_ui keeps it so (#1313).
- A focused `rspec` run is no longer held to the 90% coverage floor, which it could only meet within ten minutes of a full run; the floor applies to the whole suite and `bin/parallel-rspec`'s merge, as documented (#1315).
- README's project tree lists only files that exist, and a docs spec fails when it names one that is gone; the QA OAuth walkthrough and the email doc's registration steps name the current sign-in methods.
- Links in a document body reach AAA contrast in a personal workspace's dark theme (`--color-accent` moves from `neutral-400`, 6.78:1, to `neutral-300`).
- The rich-text editor shows its formatting toolbar: Lexxy's stylesheet is linked and themed onto the semantic tokens, and focus rings the whole field instead of drawing the browser's outline inside it.
- A fresh fork's suite no longer fails the cookie-classification doc check: the security doc names Rails' session cookie as `_<app_name>_session`.
- `bin/fork`'s verify step no longer reports the template's own code namespaces (the `ModelRails/` cop department, `window.ModelRails`) as rename misses.
- A suspended user's OAuth callback no longer links the provider or accepts a parked invitation before the refusal (#1129).
- Deleting a user no longer raises on their pending challenge rows, and a user who created a project, resource or join link is refused with an error naming what they still own; a guard spec derives every foreign key into `users` from the schema (#1248).
- A magic link superseded by a newer one is no longer read as a replay when its signed-in owner clicks it; redemption and supersession are told apart (#1083).
- Five developer-doc statements now describe the tree: which mail a suspended address still receives, the visibility suspension rows are written at, the page-rendered flash's unobserved reader behaviour (#1267), the retired draft-count caveat, and when the reconciler logs its warning.
- Dependabot no longer proposes `modelrails_ui` downgrades: the git-tag gem is ignored in `.github/dependabot.yml` and bumped by hand, with a template invariant keeping it so (#1261).
- A malformed email reaches the server's error summary instead of the browser's validation bubble (#1117).
- The actor snapshot cannot be caller-supplied, and a deleted actor no longer shortens the most-active strip (#1122).
- Flash messages asserted in the workspace, account-settings, sign-in and client-area specs (#526).
- Draft recovery announces the right field count (modelrails_ui v0.23.1).
- Component previews and embeds fetch no third-party host under test (#1207, #1233).
- Operations member-order spec measures the member list, not the page (#1231).
- Signal chip borders meet the 3:1 non-text floor (modelrails_ui v0.23.0).
- Toast icons meet the 3:1 non-text floor in both themes (#1236).
- Form controls keep their invalid state in forced-colors mode (modelrails_ui v0.23.0).
- Docs search no longer drops a query typed before the index loads (markdowndocs 0.11.4, #1074).
- The inline theme script stops reading a cookie fallback it can never reach (#624).

### Changed

- The `modelrails_ui` pin moves to `v0.22.0`, and **the `navigation_menu` fork divergence retires**. That component's `PANEL_LINK` carried a 44px AAA target floor this app had added locally, which meant every re-vendor had to be hand-merged or it would silently revert — nothing would fail, because the app never audits that component in isolation. The gem ships the fix now, so the vendored copy is plain again and the FORK DIVERGENCE note is gone. Flyout links are taller wherever the component renders. `radio_group` also stops building ids from the raw `name:`, so the join-policy picker's ids lose their brackets — `workspace[join_policy]_invite` becomes `workspace_join_policy_invite`. Nothing here needed a spec change: the picker's examples read ids from the attributes that carry them rather than hardcoding the shape, which is what made them forward-compatible. (modelrails_ui #246/#247)

### Changed

- The workspace join-policy picker is `UI::RadioGroup`. It was two hand-rolled `f.radio_button` calls — the only field on that form that never passed through the design system — and it was blocked until the component gained a per-item `description:`. Three things were wrong beyond the styling. The options had **no group semantics at all**, so a reader met two loose radios with no name for the choice; the group is now named by the card's own heading. Each option's help text sat **inside its `<label>`**, making it part of the radio's accessible name — "Shareable join link Anyone with the link can join this workspace…" was announced as the option itself; it is now a description, read after the name. And when the instance has not opted into open link, that explanation was in the label too; it now leads the description, because for an option you cannot choose, why it is unavailable is the fact you came for. The 44px row target and the disabled branch both survive, and nothing asserted any of this before — the picker had no test. (#738, modelrails_ui #137)

### Fixed

- Two bordered cards stop disappearing into the page. The activity feed and the workspace join-policy section were still painted `bg-surface` — the **page** colour — so once `<body>` moved to `bg-surface` as the paired half of the v0.19.0 surface ruling, both read as a bare outline rather than a card. The activity feed's own comment says its border exists so the feed "reads as an intentional module rather than text floating in whitespace", which is exactly what the page colour defeated. A code-smell spec ported from the gem's `test_container_surface.rb` now scores every bordered container in the app's views and components, so a third answer cannot appear quietly. It ignores a variant-prefixed token: `hover:bg-surface-sunken` on a button is a hover state on a control, not a container fill, and counting it flagged two perfectly correct buttons.

### Changed

- The `modelrails_ui` pin moves to `v0.21.0`, and the icon workarounds it was waiting on come out. Anchored panels — `popover`, `hover_card`, `dropdown_menu`, `menubar`, `navigation_menu`, `date_picker`, `timepicker`, `tooltip` and the sidebar rail — now carry a ceiling resolved against the viewport, so a panel can no longer be wider than the screen; `position-try-fallbacks` never covered that, because flipping needs room on the other side. `empty_state` spaces its own slotted icon, so the `mb-3` every call site carried is gone. A responsive spec proves the ceiling reaches **compiled CSS** rather than just shipping as a class: the gem's browser lane serves no stylesheet, so upstream could only prove the class exists, and `calc(100vw-2rem)` is invalid CSS unspaced — a wrong spelling would have passed the gem's gate and bounded nothing. It also asserts the ceiling grows with the viewport, which a fixed rem value would fail. (modelrails_ui #211/#241)
- `date_picker` and `sidebar` catch up to the gem after sitting behind it: the date picker gains the typed entry path it has lacked since v0.17.0, and the sidebar finally emits the `id` it was already computing. Neither has a call site in this app, which is why both drifted unnoticed — and why closing the gap now costs nothing. `navigation_menu` was **hand-merged instead of regenerated**: its `PANEL_LINK` carries a 44px AAA target floor the gem does not ship, and `--force` reverts it silently, since this app never audits that component in isolation. The constant now says so and points at the upstream issue (modelrails_ui #246). `Metrics/ClassLength` now skips the two vendored trees: the gem's addition pushed `form_builder` one line over the app's limit, and a size complaint about generator-owned code is unactionable — shortening it is fork divergence, and the next `modelrails_ui:add` reverts it. Everything the app writes is still measured.

### Changed

- The `modelrails_ui` pin moves to `v0.20.0`, and the quiet-hours day picker retires into `chip_group` — the gem-side form-submission mode #739 was waiting for. It keeps native checkboxes and a server round-trip per click rather than `toggle_group`'s client-side state, so the bespoke `quiet-hours-warning` controller keeps working unchanged and the component's own empty sentinel replaces the hand-written one. The `<fieldset>` around it goes: the component **is** the group, and nesting it inside a second grouping container made a reader announce the same set twice — it now takes its name from the visible label and points at the empty-days warning itself. The chips also move off a `focus-visible:ring` onto the offset outline the design system requires, since a box-shadow ring is clipped by `overflow:hidden` ancestors and vanishes in forced-colors mode (WCAG 2.2 2.4.7), and `auto-submit` is wired once on the form instead of on each of the seven chips, because `change` bubbles. (Addresses #739; modelrails_ui #169)
- Every hand-rolled empty-state block is now `UI::EmptyState`: the shared `shared/_empty_state` partial behind 13 call sites, the passkeys card, and both markdowndocs states. Two defects retire with the copies — the passkeys card painted `bg-surface` on a bordered container, which is the colour of the page beneath it, and the markdowndocs states emitted an `<h3>` for transient content, injecting a heading at an arbitrary level into the page outline. Titles are a `<p>` now. The one-line "no activity" notice in `settings/sessions` is deliberately left alone: it is a row-level notice, not an empty-state block. Slotted icons carry `mb-3` at the call site until the component spaces its own icon slot (modelrails_ui #241). (modelrails_ui #135)

### Fixed

- Every list-emitting vendored component now carries an explicit `role="list"`: `timeline`, `stepper`, `breadcrumb`, `navigation_menu`, `mega_menu`, `footer` and `file_input` (`list_group` already had it). Tailwind's preflight sets `list-style: none`, and Safari/VoiceOver drop the implicit list role once the marker is gone — no item count, no per-item set position, no rotor entry. `error_summary` keeps its marker and is the one documented exemption. A code-smell spec derives the list-emitting set from the components themselves, so a new one cannot reopen the gap by not being listed. WCAG 2.2 1.3.1. (modelrails_ui #190/#195)
- `timeline` and `stepper` normalize attribute keys before merging a caller's `**html_attrs`, so a `role:`/`"role"` override replaces the default instead of emitting a second `role` attribute. For `stepper` this also applies to its default `aria-label`.

### Changed

- The `modelrails_ui` pin moves to `v0.19.0`, and the page background moves with it. `bg-surface` is the **page**, so a container painted with it was the same colour as the ground beneath it — the card family now agrees on `bg-surface-raised`, and `<body>` moves from `bg-surface-raised` to `bg-surface` so cards lift off the page instead of flattening into it. The two halves have to land together: taking the pin without the `<body>` change would make every card-shaped container invisible but bordered. Proven by the AAA axe gate in both themes, which is the only place this can be proven — the gem's CI disables `color-contrast`. (modelrails_ui #210)
- The vendored `combobox` **retires its fork divergence**. Its three accessibility fixes — options are not tab stops, focus leaving the widget dismisses it, a pointer selection keeps focus on the input — now ship in the gem, so the app's copy and the gem's agree again. Filtering also announces how many results remain, from a live region registered before the text arrives. (modelrails_ui #217/#218/#166)
- The `modelrails_ui` pin moves to `v0.18.0`. Nothing rendered here changes: 0.18.0's breaking change is the `error_summary` DOM shape, which this app already used — the gem adopted the app's shape rather than the reverse. With it the last behavioural difference in that component is gone, so its **Error summary fork note is retired**; the app's copy and the gem's now agree.

### Fixed

- `UI::Popover` merges a caller's `trigger_attrs:` `data:` hash one level deeper instead of flat, so a caller's hooks survive alongside the component's Stimulus wiring rather than being silently dropped. Keys are stringified first, since `content_tag` de-duplicates neither `:key` against `"key"` nor the reverse. The ledger's range trigger drops the flat-string-key workaround this bug forced. (modelrails_ui #204)

### Changed

- The `modelrails_ui` pin moves to `v0.17.0`, which gives `date_picker` a typed path: a date can be entered directly instead of only reached by walking the calendar grid. This app has no `date_picker` call site — the ledger's From/To range uses native date inputs, chosen precisely because that gap existed — so the bump changes nothing rendered here today. It keeps the pin current, and it makes adopting the component in the range popover a real option rather than a downgrade.

### Changed

- The `modelrails_ui` pin moves to `v0.16.0`. The vendored component headers merged earlier today are three-line pointers into `docs/components/` in the gem, and `v0.15.1` shipped the pre-migration docs — so those pointers resolved to files carrying none of the prose the headers had dropped (0 "When to use" sections against 56, 4 accessibility contracts against 66). The bump makes every pointer resolve to what it names.

### Added

- The operations ledger names the most active people for whatever filter is applied, above the table. Counts come from a grouped count over the whole filtered scope on an indexed column, so they describe every matching row rather than the rows on the current page, and only the handful of names shown are decrypted. Each entry narrows to that person through the same `q` pivot the row details use. Rows with no actor are left out — the strip answers *who*, and System is not a who. (#1179)

### Changed

- The operations ledger's Workspace filter becomes a server-side search past 100 workspaces, instead of rendering every kept workspace into the filter band on every full-page navigation. The switch is automatic because a fork's instance is not being watched for the day it crosses the line. The list is never silently capped — a search offering more matches than it shows says how many it left out — and `?workspace=<slug>` keeps working on both shapes. (#1166)

### Breaking

- **Fork invariant — an instance has operators, and `/operations` is theirs.** `Operatorship` (a `Discardable` row per operator in a new `operatorships` table, partial unique index on kept rows) marks who administers the instance from above the workspaces. `Operations::` controllers under `/operations` — workspaces, users, activity, operators; 16 routes — answer 404 to anyone else and force reauthentication on every request. Under the `:shared` preset the seed grants the bootstrap owner an operatorship; elsewhere `rails operators:grant[email]` mints the first one. Landing with it: user suspension is a reversible hold (`users.suspended_at`; `User#suspend!(by:)` / `#unsuspend!(by:)` — sign-in refused at the one session funnel, sessions ended, memberships untouched) and replaces the evicting `users:suspend`; `User#unlock!(by:)` is the audited administrative lockout clear; `ActivityLog.record_security_event!` takes `actor:` and `visibility:` and is the one writer for every `SECURITY_ACTIONS` member (five new: `user.suspended`, `user.unsuspended`, `user.unlocked`, `operatorship.granted`, `operatorship.revoked`); `Suspendable#suspend!` / `#unsuspend!` are guarded inside their transaction and return an outcome; `Workspace#owner` ignores discarded memberships; `Workspace.create_for_owner_email` is the operator-create verb; `Settings::ReauthenticationsController` and `Settings::ReauthenticationCodesController` skip the onboarding requirement; `TENANCY_WORKSPACE_CREATION=disabled` binds operators too. (#1127; closes #1120)

  | Failure in your fork | Remedy |
  |---|---|
  | `rails users:suspend` no longer removes the user from their workspaces | It is a sign-in hold now (`users:unsuspend` lifts it); remove memberships from the members page or with `Membership#deactivate!` |
  | `NoMethodError: suspend_access!` | `user.suspend!(by:)`; nothing is discarded any more |
  | `ArgumentError: missing keyword :by` from `User#unlock!` | Pass the acting user — `by: Current.user`, or `by: nil` from a script |
  | `if workspace.suspend!` treated as a boolean | Case on `:suspended` / `:already_suspended` (and `:unsuspended` / `:not_suspended`) |
  | A direct `ActivityLog.create!` for a `SECURITY_ACTIONS` action fails `security_events_route_through_writer_spec` | Route it through `record_security_event!` (`actor:` / `visibility:` override the self-event shape), or register a best-effort writer in `spec/support/security_event_writers.rb` |

- Fork invariant — the workspace switcher is one partial, and it left the header. `shared/_workspace_switcher.html.erb` (its trigger `shared/_workspace_switcher_trigger.html.erb`) heads the sidebar and, on phones, renders again in the content column above the section tabs with `id_suffix: "-mobile"`; the header no longer renders it and the hamburger no longer lists workspaces. Gone with it: `shared/_workspace_identity_bar`, `shared/_workspace_name_link`, `shared/_workspace_context_banner`, and the `workspaces.context_banner.*`, `workspaces.identity_bar.*` and `workspaces.overview.customize.*` locale keys. A fork that overrode any of those re-applies the change to the one partial; the rename broadcast (`workspaces/update.turbo_stream.erb`) replaces the whole trigger, so markup a fork adds inside it must stay free of focusable elements. (#1078, #1089)
- Fork invariant — `.kamal/secrets` holds references, never literals. `spec/code_smells/kamal_secrets_hold_no_literals_spec.rb` fails the suite on any tracked `.kamal/secrets*` value that does not start with `$` — `$VAR` from the environment or `$(…)` from a password manager — and the deployment guide now says where the values live instead of instructing them into the tracked file. Failures name keys and line numbers, never values. (#1081)
- **Fork invariant — static pages are one resource; the OmniAuth failure page is its own controller.** `PagesController` has one action, `show`, keyed by page name (`PagesController::PAGES`, the templates under `app/views/pages` as the allowlist); `config/routes/app.rb` declares `root to: "pages#show", defaults: { id: "home" }` and `resources :pages, only: :show, path: "", constraints: { id: /about|privacy|contact/ }`, so `/about`, `/privacy`, and `/contact` keep their URLs and become `page_path(:about)` and siblings (`about_path`, `privacy_path`, `contact_path` are gone). Both files are fork-owned (`merge=ours`), so an existing fork keeps its own; a new fork starts from this shape, and adds a page by adding its template, its name to the constraint, and its name to `PAGES`. `GET /auth/failure` (the path OmniAuth's `on_failure` fixes) is `OmniauthFailuresController#show`; `OmniauthCallbacksController#failure` is gone. With this, every routed action in base's own controllers is one of the seven REST actions (`bin/rails routes` filtered as in the playbook's conventions standard → nothing left). Closes the second arc on #1007.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError: undefined method 'about_path'` (or `privacy_path`, `contact_path`) in a shared view or spec | `page_path(:about)` etc.; or keep your own routes file, which `merge=ours` already does |
  | `AbstractController::ActionNotFound` for `omniauth_callbacks#failure` from your own `on_failure` route | Point it at `omniauth_failures#show` |
  | `template_invariants_spec` expecting `root "pages#home"` | The invariant now accepts any `root` line in `config/routes/app.rb` |

- **Fork invariant — the passkey ceremonies are resources.** Each WebAuthn ceremony is two creates on two nouns: the challenge, then what the signature earns. `POST /passkeys/registration/{options,verify}` → `POST /passkeys/registration/{challenge,credential}` (`Passkeys::Registration::ChallengesController#create`, `Passkeys::Registration::CredentialsController#create`); `POST /passkeys/authentication/{options,verify}` → `.../authentication/{challenge,session}` (`Passkeys::Authentication::ChallengesController`, `Passkeys::Authentication::SessionsController`); `POST /passkeys/reauthentication/{options,verify}` → `.../reauthentication/{challenge,confirmation}` (`Passkeys::Reauthentication::ChallengesController`, `Passkeys::Reauthentication::ConfirmationsController`). The three old controllers are gone with their route helpers; `Passkeys::RegisterCeremony`, `Passkeys::AuthenticateCeremony`, the error classes, the gates, and the sign-in rate limit are unchanged. The `webauthn` Stimulus controller reads its URLs from `data-webauthn-*-url-value` attributes, which the three views now fill with the new helpers; the JS is untouched. Part of the second arc on #1007.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError` on `passkeys_registration_options_path` / `_verify_path` (or the authentication / reauthentication pair) | `passkeys_registration_challenge_path` / `passkeys_registration_credential_path`; `passkeys_authentication_challenge_path` / `passkeys_authentication_session_path`; `passkeys_reauthentication_challenge_path` / `passkeys_reauthentication_confirmation_path` |
  | A fork subclassing `Passkeys::RegistrationsController` (or the other two) | Subclass the two controllers the ceremony became |
  | Custom JS posting to `/passkeys/*/options` or `/verify` literally | Read the URLs from the view's data attributes, as base's controller does |

- **Fork invariant — ownership transfer is a resource.** `PATCH /workspaces/:slug/members/:id/transfer_ownership` (`Workspaces::MembersController#transfer_ownership`) is `POST .../members/:id/ownership_transfer` (`Workspaces::Members::OwnershipTransfersController#create`, `workspace_member_ownership_transfer_path`). `MembershipPolicy#transfer_ownership?` and `Membership::Ownership#transfer_ownership_to!` are unchanged. Flash key: `workspaces.members.ownership_transfers.create.transferred`. Part of the second arc on #1007.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError: undefined method 'transfer_ownership_workspace_member_path'` | `workspace_member_ownership_transfer_path(workspace, membership)` with `method: :post` |
  | Missing translation `workspaces.members.transfer_ownership.transferred` | `workspaces.members.ownership_transfers.create.transferred` |

- **Fork invariant — the undo-and-resend actions are resources.** Five member/collection actions become nested resources: `POST /workspaces/:slug/invitations/:id/resend` → `Workspaces::Invitations::ResendsController#create` at `.../invitations/:id/resend` (`workspace_invitation_resend_path`); `POST /settings/connected_accounts/:id/resend_verification` → `Settings::ConnectedAccounts::VerificationResendsController#create` at `.../connected_accounts/:id/verification_resend`; `PATCH /workspaces/:slug/members/:id/reactivate` → `POST .../members/:id/reactivation` (`Workspaces::Members::ReactivationsController#create`); `PATCH .../resources/:id/reposition` → `PATCH .../resources/:id/position` (`Workspaces::Projects::Resources::PositionsController#update`, same `resource[position]` param); `POST /settings/notifications/mark_all_read` → `POST /settings/notification_readings` (`Settings::NotificationReadingsController#create`, the bulk twin of `Settings::Notifications::ReadingsController`). The five old actions and their route helpers are gone; the policy predicates (`resend?`, `reactivate?`, `reposition?`, `mark_all_read?`) are unchanged and called explicitly. Rate limits moved with their actions at the same thresholds. Flash keys follow the controllers: `workspaces.invitations.resends.create.*`, `settings.connected_accounts.verification_resends.create.*`, `workspaces.members.reactivations.create.reactivated`, `settings.notification_readings.create.success` (the `notifications.index.mark_all_read.*` dialog copy stays). Part of the second arc on #1007.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError` on `resend_workspace_invitation_path`, `reactivate_workspace_member_path`, `resend_verification_settings_connected_account_path`, `reposition_workspace_project_resource_path`, or `mark_all_read_settings_notifications_path` | The helpers above; note reactivate is now `method: :post` |
  | A fork's own `rate_limit ... only: :resend` (or `:resend_verification`) on the old controller | Move it to the new controller's `create`, or drop it — base's limit is already there |
  | Missing translation under `workspaces.invitations.resend`, `settings.connected_accounts.resend_verification`, `workspaces.members.reactivate`, or `notifications.index.mark_all_read.success` | The keys above |

- **Fork invariant — the sign-in steps are resources.** `POST /session/lookup` is `Sessions::LookupsController#create` (path and `session_lookup_path` helper unchanged; `SessionsController#lookup` is gone, with its `deliver_magic_link`). `GET /session/password` is `GET /session/password/new` (`Sessions::PasswordsController#new`, `new_session_password_path`; `session_password_form_path` is gone). `POST /magic_link_callback/:token/sign_in` is `POST /magic_link_callback/:token/session` (`MagicLinkCallbacks::SessionsController#create`, `magic_link_callback_session_path(token)`; `magic_link_callbacks#sign_in` and `magic_link_callback_sign_in_path` are gone). The form object `EmailLookupForm` is `EmailLookup`. Views moved with their actions: `sessions/{check_email,closed,email_error}` to `sessions/lookups/`, `sessions/password_form` to `sessions/passwords/new`. Locale keys: `sessions.lookup.invalid_email` → `sessions.lookups.create.invalid_email`; `sessions.lookup.password_prompt` and `sessions.password_form.*` → `sessions.passwords.new.*`. Third of the three PRs on #1007's original list; the route audit that followed found seventeen more verb actions (passkey ceremonies, resend, reactivate, transfer ownership, reposition, mark-all-read, the static pages, the OmniAuth failure callback), tracked on the issue.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError: undefined method 'session_password_form_path'` | `new_session_password_path(email_address:)` |
  | `NoMethodError: undefined method 'magic_link_callback_sign_in_path'` | `magic_link_callback_session_path(token)` |
  | `NameError: uninitialized constant EmailLookupForm` | `EmailLookup` |
  | `ActionView::MissingTemplate sessions/check_email` from a fork's own render | The template is `sessions/lookups/check_email`; render it from a controller under `Sessions::` or pass the full path |
  | Missing translation `sessions.password_form.*` / `sessions.lookup.*` | `sessions.passwords.new.*` / `sessions.lookups.create.invalid_email` |
  | A fork's `allow_unauthenticated_access only: %i[... lookup password_form]` on `SessionsController` | Drop the two names; the new controllers allow it for all their actions |

- **Fork invariant — the identity picker hubs are resource shows.** `GET /account/avatar/hub` (`Settings::AvatarsController#hub`) is now `GET /account/avatar` (`#show`; `Settings::AvatarPolicy#show?` added). `GET /workspaces/:slug/identity_picker_hub` (`WorkspacesController#identity_picker_hub`) is now `GET /workspaces/:slug/logo` (`Workspaces::LogosController#show`, authorized by the new `Workspaces::LogoPolicy#show?`; `Workspaces::ProfilePolicy#identity_picker_hub?` is removed). The `shared/identity_picker_hub` partial and its locals are unchanged; only `hub_url` values change. `WorkspaceNavHelper::WORKSPACE_SETTINGS_ENDPOINTS` names `workspaces/logos` instead of the old action. Second of the three PRs closing #1007.

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError: undefined method 'hub_settings_avatar_path'` | `settings_avatar_path` |
  | `NoMethodError: undefined method 'identity_picker_hub_workspace_path'` | `workspace_logo_path(workspace)` |
  | `NoMethodError: undefined method 'identity_picker_hub?' for Workspaces::ProfilePolicy` | Authorize with `Workspaces::LogoPolicy` (`show?`) |
  | A fork's own picker route reusing `hub_url:` with a custom action | Give it a `show` on a singular resource; the partial does not care |

- **Fork invariant — archive and restore are a resource, not member actions.** `PATCH /workspaces/:slug/archive` and `/unarchive` are now `POST` and `DELETE /workspaces/:slug/archival` (`Workspaces::ArchivalsController`); the same for projects under `.../projects/:slug/archival` (`Workspaces::Projects::ArchivalsController`). `WorkspacesController#archive/#unarchive` and `Workspaces::ProjectsController#archive/#unarchive` are gone, with their route helpers. The policy predicates (`archive?`, `unarchive?`) and the models' `archive!`/`unarchive!` are unchanged; the `shared/archived_banner` partial's restore button now submits `DELETE`. Flash keys moved to the controller scope: `workspaces.archivals.{create,destroy}.success`, `workspaces.projects.archivals.{create,destroy}.success`. First of the three PRs closing #1007 (REST with no cited exceptions).

  | Failure in your fork | Remedy |
  |---|---|
  | `NoMethodError: undefined method 'archive_workspace_path'` (or `unarchive_…`, `…_workspace_project_path`) in a view or spec | `workspace_archival_path(workspace)` with `method: :post` to archive, `:delete` to restore; `workspace_project_archival_path(workspace, project)` likewise |
  | `AbstractController::ActionNotFound` for `workspaces#archive` from a route in your `config/routes/app.rb` | Point it at your own controller, or drop it — the resource route is already in base |
  | A `shared/archived_banner` render whose `restore_path` still names a PATCH endpoint of your own | Give it a DELETE endpoint, or pass your own `button_to` |
  | Missing translation `workspaces.archive.success` / `workspaces.unarchive.success` | Use the `archivals.create.success` / `archivals.destroy.success` keys |

- **Fork invariant — notifications cannot be deleted by hand, and "Never" retention is gone.** `Settings::NotificationsController#destroy` and `#destroy_all_read`, their routes, `NotificationPolicy#destroy?` and `#destroy_all_read?`, and their locale keys are removed; a read notification leaves the list only through the user's retention window, an unread one never. `NotificationPreferences::RETENTION_FLOORS` is removed: a security-category notification expires like any other row, and the audit sweep's `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR` is now the only floor. Users who had chosen "Never" are capped at 365 days by a best-effort backfill migration; the reader (`NotificationPreferences#retention_days`) is the invariant, so a row the backfill misses still reads correctly. **The first cleanup sweep after this deploy is the largest your app will ever run**: it removes, with no undo, every read notification the old code was holding back — "Never" users' history older than 367 days and every security-category row past its owner's retention. Users with no preferences row, whom the old job skipped entirely, are now swept at the default too. Before deploying, count what it will take: `UserPreferences.where("json_type(notification_preferences,'$.retention_days') = 'null'").count` (users affected), `Noticed::Notification.where.not(read_at: nil).where("read_at < ?", 367.days.ago).count` (rows removed because "Never" is retired), `Noticed::Notification.where(type: ApplicationNotifier.notification_types_for("security")).where.not(read_at: nil).where("read_at < ?", 32.days.ago).count` (security-category rows the old floor was holding; worst case at the shortest retention choice plus grace), and `UserPreferences.where("json_type(notification_preferences,'$.retention_days') NOT IN ('integer','null') AND json_type(notification_preferences,'$.retention_days') IS NOT NULL").count` (rows with a non-integer retention value; fix these by hand, the sweep isolates them per user and reports the user id). `NotificationPreferences#retention_days` never returns `nil` now; a fork branching on `retention_days.nil?` silently takes the other branch — grep for it. Do not deploy in the ten minutes after 03:00 in your instance's zone: the sweep runs then (`config/recurring.yml`), the migration lands at container boot, and SQLite has one writer.

  | Failure in your fork | Remedy |
  |---|---|
  | `AbstractController::ActionNotFound` for `settings/notifications#destroy` or `#destroy_all_read` from a route in your `config/routes/app.rb` | Point the route at your own controller, or drop the feature |
  | `NoMethodError: undefined method 'destroy_all_read?' for NotificationPolicy` | Re-add the method in your fork's policy if you kept a bulk delete |
  | No error — `NotificationPolicy#destroy?` falls through to `ApplicationPolicy#destroy?`, which returns `false`, so a kept delete is refused with a silent `Pundit::NotAuthorizedError` | Re-declare the method in your fork's policy |
  | `NameError: uninitialized constant NotificationPreferences::RETENTION_FLOORS` | Use `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR` |
  | Your preferences form submits `retention_days: "never"` and gets a 422 | Remove the option; the reader now caps an explicit null at 365 |

- **Fork invariant — `InvitationMailer` is parameterized.** Call it as `InvitationMailer.with(invitation: invitation).invite` / `.invite_client`; the positional form is gone. A single `before_action` now gates every action on `Invitation#deliverable?`, so a fork's own `InvitationMailer` methods inherit invitee-block suppression without touching them.

  | Failure in your fork | Remedy |
  |---|---|
  | `ArgumentError: wrong number of arguments` on `InvitationMailer.invite(inv)` | Switch to `InvitationMailer.with(invitation: inv).invite` |

- **Fork invariant — destroying a user now destroys the invitations they sent.** `User#sent_invitations` is `dependent: :destroy`; it was `:nullify` against a `NOT NULL` column, which raised on the first user destroy. Two associations join it: `accepted_invitations` is `:nullify`, because `accepted_by_id` is a nullable column carrying a real foreign key and would otherwise raise `InvalidForeignKey` for any user who ever accepted an invitation, and `invitation_blocks` is `:delete_all`. A fork that expects sent invitations to outlive their sender must keep its own record of them (#816).
- **Fork invariant — `granted_by` and `self_join` are mutually exclusive, and `self_join` has a closed grade set.** They answer different questions (who granted this vs who acted), so `Workspace#admit` and `Membership#reactivate!` raise `ArgumentError` when handed both, and a `Membership` validation refuses the combination — plus any `self_join` outside `nil` / `false` / `true` / `:onboarding` — on every construction path, a fork's own direct `memberships.create!` included. A fork adding a grade must list it in `Membership::SELF_JOIN_GRADES` **and** opt it into `chosen_self_join?`, which asks whether the grade IS the chosen one rather than whether it is anything but `:onboarding`: an unrecognised grade now stays silent instead of sending the joiner an orientation notice.
- **Fork invariant — every in-memory instance of a membership row that saves inside one transaction must carry the provenance markers.** Rails runs a row's commit callbacks on the LAST instance of it saved in a transaction (`run_commit_callbacks_on_first_saved_instances_in_transaction` is `false`), so the instance that reconciles a row — not the one that INSERTed it — is what the actor rule reads. `Workspace#admit` assigns `granted_by` / `self_join` to the existing membership before any save for exactly this reason; a fork adding a second write of the same row inside `Signupable#commit_signup_atomically`'s transaction has to do the same, or the actor exclusion silently disappears.
- **Fork invariant — every `suppressed_at` write is callback-free** (`update_column` / `update_all` / create attributes), deliberately: `Trackable` would otherwise publish the stamp to the workspace activity feed as an ordinary update and hand a blocked inviter a detection oracle. A fork that promotes the audit trail to strict writes must keep suppression out of it; the compensating signal is the admin-visibility `invitation.delivery_suppressed` row.
- **Personal data is encrypted at rest, and production refuses to boot without the keys.** `users.email_address` / `pending_email` / `first_name` / `last_name`, `authentications.email` / `uid`, `invitations.email` / `company_name`, `magic_link_tokens.email`, and `client_accesses.company_name` are Active Record Encryption columns — deterministic only where a finder or unique index needs it. Before deploying: `bin/rails db:encryption:init` and paste the block into the production credentials ([Forking](/docs/developer/forking#bootstrap-secrets-and-configuration)); the production preflight names the missing key otherwise. A development database created before this release is not readable — `bin/rails db:reset`. The template ships no conversion for existing rows; Rails' own path (`support_unencrypted_data`, `extend_queries`, `record.encrypt`) is in the Active Record Encryption guide under "Migrating Existing Data" (#902).
- **libvips 8.13+ and ruby-vips 2.2.1+ are now required** — Active Storage raises at boot below either. The production image, devcontainer and CI already satisfy this; custom images may not.
- **BMP, ICO and PSD attachments no longer generate variants** — `config/initializers/active_storage.rb` drops them from `variable_content_types` so they render as a file chip, rather than an image whose representation URL raises `Vips::Error` when fetched. Forks that legitimately transform those formats can re-enable the specific libvips operation in an initializer.
- **Forks that ran an affected Rails version with untrusted uploads should rotate their secrets** — see "Responding to a Secret Exposure" in `/docs/developer/security`.
- **Fork invariant — your top role must stay a permission superset.** A role can now be granted only by someone who already holds every permission it confers, so any custom permission you add (e.g. `manage_billing`) must also be granted to the **Owner** role. If it isn't, no one — not even an Owner — can assign the role that uses it, and it silently drops out of every role picker. Backfill existing Owner rows with a data migration (`seeds.rb` won't touch already-seeded workspaces). See [Extending](/docs/developer/extending).
- **`RAILS_HOST` is now required to boot in production.** A preflight initializer raises when it is unset or a placeholder, and `config.hosts` (DNS-rebinding protection) is derived from it. Previously a missing host silently pointed every mailer link (magic links, invitations, resets) at `example.com` — killing passwordless sign-in — while the app booted green. Set `RAILS_HOST` in your deploy env before upgrading (#601).
- **Fork invariant — every external GitHub Action must be SHA-pinned.** All 35 `uses:` refs are pinned as `owner/repo@<40-hex-sha> # <tag>`, a zizmor workflow audit runs in CI, and a template invariant fails the suite on any unpinned external ref — **including a fork's own workflows** (`.github` is not `merge=ours`, so the invariant arrives on sync). The `# <tag>` trailer is load-bearing (Dependabot reads it to bump pins); action bumps now arrive as one grouped weekly PR to keep the pin churn tolerable (#663).
- **Sending an invitation now requires a verified email address.** Every invitation surface — workspace, project, client and first-run onboarding — refuses a sender who has not proven control of their own mailbox. A fork that added a fifth surface should `include InvitationSending` on it.
- **Setting a password no longer marks your email verified.** `Settings::PasswordsController#create` used to stamp `verified_at` on a freshly minted email authentication, which proved control of the session and nothing about the mailbox — enough, before this release, to satisfy the invite gate above with no email round trip. It now creates the authentication pending and shows the standard verify-your-email prompt. Sign-in is unaffected (it authenticates against `password_digest`). Forks relying on password-set as an implicit verification step inherit this on sync.
- **The `:user` factory now creates a verified email authentication by default.** Every production signup leaves at least one authentication (magic-link: verified email row; password-set: pending email row; OAuth: verified provider row), so a user with none was a state the app could not reach, and `User#can_invite?` answered `false` for the universal case. The default is the magic-link shape; the exceptional states are traits: `:with_verified_email_auth` is **gone** (it is the default now), `:with_email_auth` is **renamed `:unverified_email`**, and the authless state is `:no_authentications`. Factory emails are now sequence-prefixed (`user-N-…`) so the mirrored `(provider, uid)` row cannot collide across examples, and an unknown `email_authentication:` transient value raises instead of guessing. `spec/` is not a fork seam, so this arrives on sync — upstream touched ~60 call sites across 12 spec files. What you will see, and what to do:

  | Failure in your fork's specs | Remedy |
  |---|---|
  | `KeyError: Trait not registered: "with_verified_email_auth"` | Delete the trait — it is the default now |
  | `KeyError: Trait not registered: "with_email_auth"` | Rename to `:unverified_email` |
  | `Validation failed: Provider has already been taken` | The spec hand-builds an email auth on a factory user. Drop the hand-build (you wanted the default), or start from `create(:user, :no_authentications)` if it builds a different row |
  | An expectation flips with no error — e.g. `expected … not to be can_invite`, or a verify-email banner assertion | The spec assumed a bare `create(:user)` was unverified. Name `:unverified_email` or `:no_authentications`. This one has no loud failure — grep your specs for assertions that depend on a user starting unverified |

  `create(:authentication)` now builds its user with `:no_authentications`; if you pass `user:` explicitly, that user must carry the trait too (#850).

### Added

- A fork names its nouns once. `config/vocabulary.local.yml` (fork-owned, `merge=ours`) overrides `workspace` and `project` (singular and plural); template copy says `%{workspace}`/`%{project}` and a boot-time backend hook fills the tokens, so every upstream string — present and future — renders in the fork's words. Two code-smell specs keep upstream honest (no bare noun in locale values; every interpolation token supplied). Eleven strings were reworded so no indefinite article precedes a noun. Models, routes, URLs and the user docs are unchanged by design (#1109). During the rewrite `%{project}` turned out to already carry a project's name in three strings (the second-noun twin of #1108); it is `%{project_name}` now, with a spec that counts the noun once and the name once. A third code-smell spec makes spec copy assertions go through `I18n.t`, with an allowlist for preview fixture text, so a renamed fork's suite stays green.
- `bin/fork` works from a fork of a fork. On a GitHub fork with no `upstream` yet, and nothing else naming the template, it asks `gh` for `origin`'s parent and records that in `.fork.yml` for `bin/setup` (not on the clone path, where `--origin` marks `origin` as the template itself). `--template URL` names the template explicitly and always wins: an `upstream` equal to it counts as configured, an `origin` equal to it gets the template's remote surgery. Equality only, `.git`-insensitive; the `/modelrails_base` name anchor is unchanged.
- `.rubocop/app.yml`, a fork-owned (`merge=ours`) seam for RuboCop overrides, and `.rubocop/house.yml`, base-owned, holding the eight house cops' config; `.rubocop.yml` inherits both after the todo file. A fork turns a house cop off in `app.yml` with the reason above it and never touches base's files (`/docs/developer/getting-started`, "Turning a house cop off in your fork"). The cops are on by default in every fork, as omakase is.
- `ModelRails/NoAmbientCurrentInModels`: a `Current` read anywhere under `app/models` is an offense, except in `Trackable` (the audit actor), `Tenanted`'s opt-in `for_current_workspace` scope, and `Current` itself. Ships with nothing grandfathered: #1017 removed the last one. The architecture page's "Actors are parameters" paragraph names the cop, and the message points at it.
- `ModelRails/RestfulActions`: a public method on a routed controller whose name is not one of the seven REST actions is an offense, whether it is a verb that should be a nested resource or a helper that should be private. `ApplicationController` (abstract, `helper_method` exposures) is excluded with the reason. Ships with no allowlist: the two routes arcs cleared every verb action first. `/docs/developer/extending` gains "Only the seven actions", which the message points at.
- `ModelRails/StackFloor`: a `Gemfile` line adding Devise, a JavaScript or CSS bundler, React, Sprockets, or a Redis-backed queue is an offense naming what the stack uses instead, and a `rails` requirement that cannot be satisfied by any 8.1 release is one too. `/docs/developer/getting-started` gains "The stack", which the message points at.
- `ModelRails/NoCurrentUserShim`: a `current_user` definition (`def`, `alias`, `alias_method`, `delegate`) anywhere under `app` except `ApplicationController` is an offense; the one there is the bridge Pundit and mounted engines call, and app code reads `Current.user`. The architecture page's Authorization section says so, and the message points at it.
- `ModelRails/NoI18nDefault`: a `default:` on `t`, `translate`, or `I18n.t` is an offense — in Ruby under `app` through RuboCop, and in views through erb_lint's `Rubocop` linter, enabled for this one cop. The vendored `app/components/ui` primitives are excluded (the gem's files and fallbacks). Its ERB half found the one site the greps behind the fix-first PR missed, the workspace activity feed's action label; that default is gone, `activity.actions.workspace.created` exists, and the dynamic-keys code-smell spec now proves every feed action has a label. `/docs/developer/i18n` gains "No inline defaults", which the message points at.
- `ModelRails/NoSleepInSystemSpecs`: a bare `sleep` under `spec/system` is an offense. The tick of a bounded poll (`sleep 0.05 until ...`, or a `sleep` inside a `loop`, `until`, `while`, or `times` block) and a named negative wait (a `sleep` with an inline comment naming what it waits out) pass. `/docs/developer/testing` gains "Waiting in system specs", which the message points at.
- `ModelRails/NoDefaultScope`: a `default_scope` call anywhere under `app/models` is an offense. Tenant scoping is opt-in (`Tenanted` installs none), and a default scope acts at a distance on every query, including the ones a job, the console, and an association never meant. The message names the workspace association to use instead and points at `/docs/developer/extending` ("Decide how it is tenant-scoped").
- House RuboCop cops under `lib/rubocop`, loaded by `.rubocop.yml` on top of omakase. First cop: `ModelRails/ModelConcernNamespace`, which fails a file under `app/models/<model>/` that defines its module or class in the compact `module Model::Trait` form instead of reopening the model. Every message says what broke, how to fix it, which pattern applies, and where to read more (`/docs/developer/extending`, "Per-model traits", which now carries the placement rule; closes #1002). A fork that keeps its own `.rubocop.yml` opts in with the `require:` and cop blocks base's file shows.
- The notifications index tells you how your list clears ("Once you've read a notification, we remove it N days later") and links straight to the retention control.
- A code-smell fence refuses relation-level deletes of `Noticed::Event` in `app/` and `lib/`; the future orphan-pruning job registers there by file name.
- Removing a member now notifies the people it concerns — the removed member and every workspace owner but the one who acted — with the in-app row reading "was removed" or "left" depending on who did it, and a second-person email to the removed member only. It sits in the `account_access` category, so muting workspace chatter never mutes losing access (#933).
- **Active-devices management** — `/settings/sessions` lists the devices where you're signed in (browser/OS, IP, last active), marks the current one, and lets you revoke any device or "sign out all other devices." Revoking is scoped to your own sessions.
- **`bin/fork`** — one-command fork onboarding: remote surgery, identity rename, and tenancy preset in a single commit, with provenance recorded in `.fork.yml`. Run it once after cloning, before `bin/setup`. Teammates run only `bin/setup`, which now applies the fork's recorded preset and adds the upstream remote per clone. See [Forking](/docs/developer/forking).
- Parallel test suite — `bin/parallel-rspec` runs RSpec across all cores with example-count and merged-coverage integrity gates; CI and the Lefthook pre-push gate use it, cutting CI's test job from ~14 to ~8.5 minutes (#485; further wins tracked in #486–#488).
- Runtime-balanced parallel test split — spec files split across workers by recorded per-file runtime instead of file size, evening out the slowest worker; the timing log (`tmp/parallel_runtime_rspec.log`) is written each run and cached in CI, and falls back to file-size splitting when absent (#488).
- Add opt-in encrypted form-draft recovery on invitation and project forms.
- Cancel superseded CI runs on new pushes to the same branch/PR (#489).
- `i18n-tasks` gate — `spec/i18n_spec.rb` fails the suite on missing keys and inconsistent interpolations, so CI and Lefthook both cover it with no separate step to keep in sync.
- `/docs/developer/i18n` — where locale keys live, the two gates, the lazy-key rule for private controller methods, the `date.formats` seam, and how to add a language.
- `Current.workspace!` — fail-loud workspace accessor for non-request entry points (jobs, rake, console); nil context raises instead of leaking cross-tenant reads (#603).
- **Activity-log rows are immutable once persisted** — updates and deletes raise; sanctioned sweeps go through a documented `allowed_bypasses` door (#604).
- Daily unattached-blob sweep — direct-upload blobs that never attach are purged after a 2-day grace, protecting the shared SQLite/storage volume from silent fill (#596).
- Stale WebAuthn challenges are swept on a schedule instead of accumulating forever (#612).
- i18n unused-key gate — the suite fails on locale keys nothing reads (120 dead keys removed); scanner-invisible consumers are ignored by name, and locale files route per-namespace (#614).
- File inputs display the selected file name(s) instead of the browser's default text (#627).
- Menu band: checkable menu items and a destructive item tone (#702), and nested submenus (#703).
- Vertical tabs and manual (arrow-then-Enter) tab activation (#705).
- Checkbox indeterminate state, disabled collapsible, breadcrumb ellipsis collapse, and avatar error fallback (#706).
- Command palette ranks matches fuzzily (#710); drawers support drag-to-dismiss (#711).
- Sidebar collapse state is exposed to assistive tech and no longer traps keyboard navigation (#712).
- `/docs/developer/security` outbound-request (SSRF) guidance for the first URL-accepting feature a fork adds (#664).
- `/docs/developer/extending` documents the sanctioned cross-workspace query patterns (#695) and the commenting hierarchy (#699).
- `/docs/developer/machine-clients` — the map for a fork's first non-browser entry point (MCP, API, webhooks): reproducing the tenancy boundary outside a controller, per-request MCP server construction, token-comparison guidance, and Host/Origin posture for a second exposed service.
- Security account events (password, passkey, new-device sign-in) now write audit rows; password removal now notifies (previously silently skipped). A "Recent account activity" card on `/settings/sessions` shows a user their own last ten, naming the platform on a new-device sign-in and the exact moment, in your timezone, on hover (#825, #832).
- **Decline and block** — the decline page offers a second choice that declines the invitation *and* stops that sender's future invitations from reaching that address. Blocks are email-keyed and account-independent: no account is needed, they survive the address later becoming a user, and they do not follow a user who changes address. Delivery is suppressed silently at every send site — the mailer guard, bulk invite, resend, and the expiring reminder's dispatch and mail leg — and the inviter's surfaces stay indistinguishable from an unblocked invitation. Client invitation emails now carry the decline link (their body copy already promised one), so the path reaches client invitees too. `invitation_declines#create` and the new `invitation_blocks#create` are rate-limited to 10 requests per 3 minutes per IP. Lifting a block is an operator action for now — see [Troubleshooting § Operations](/docs/developer/troubleshooting#operations) and the threat model in [Security](/docs/developer/security#invitation-blocks-decline-and-block).

- **Three new notifications, and nobody is told about their own action.** `WorkspaceCreatedNotifier` gives a creator a receipt for the workspace they just made; `WelcomeNotifier` gives a brand-new account its day-one notice (in-app only, dispatched from the registration controllers rather than a `User` callback, so it doesn't ride every factory user); `WorkspaceJoinedNotifier` orients someone who let themselves in through an open link. Alongside them, the member fan-out now excludes the actor — `WorkspaceMemberAddedNotifier` drops whoever performed the add, taken from `Workspace#admit`'s `granted_by:` / `self_join:` — so an owner who adds someone hears nothing about it and a self-joiner is no longer told, in the third person, that they joined. Re-admitting a previously removed member notifies as a fresh add does, and records the granter on its audit row.
- Copy-to-clipboard control (`ui :copy`, modelrails_ui v0.15.1) on the join-link and magic-link reveals: announced copied/failed states, honest failure over non-secure origins; the Members reveal no longer wraps the URL mid-token.
- The operations activity page is a filterable ledger: person (exact email), workspace or instance, kind, date range with a custom popover, time sort, rows per page up to 500, and per-row details with pivot links; filters apply on change inside a Turbo Frame, whose links all target `_top` so the frame serves only the on-change filter submits. `UI::TableComponent` (server-rendered table with caption, header, body and footer slots) ships with it and renders the operations workspaces list too. (#1164, #1166; modelrails_ui #201)

### Changed

- The operations activity ledger filters on one search box (`q`, with `person` kept as an alias for a release) that resolves an email address, a person's name, a workspace or a project — names matched after decryption in Ruby under a 2,000-user cap (`ActivityLog::Search`, `ActivityLog.matching_any`).
- A sortable table header now looks sortable before it is touched: `shared/_sortable_header` carries a muted up/down chevron at rest and the directional one on the sorted column, so the ledger's and the members table's sortable headers are told apart from plain ones without hovering. The glyphs are decorative; `aria-sort` on the `<th>` remains what assistive tech reads. New icon: `chevron_up_down`.
- The axe teardown's Turbo wait requires the page to stay quiet rather than believing the first quiet moment, so a frame swap that advances history no longer hands the audit a document mid-visit (an intermittent `aria-allowed-attr` on `<html>`).
- The operations activity ledger sorts by workspace name as well as by time (`ActivityLog.by_workspace_name`; instance-level rows last in either direction). Sorting by actor is a stated non-goal: names are encrypted and an under-the-cap in-memory sort would make the header conditional.
- The operations pages read as one system: `LifecycleHelper#lifecycle_status_badge` is the one status treatment (a soft badge named "Status: …", warning-tinted for a lock) on the workspaces list, a workspace's name line, a user's locked memberships and the ledger; `shared/_settings_page_header` takes `badges:` inline beside the title; `UI::TableComponent` is a filled card (`bg-surface`) and takes `scroll: :horizontal`, which scrolls only the table under a pinned toolbar and footer (the scroll region is named distinctly from the caption); `min-h-input` is the one spelling of the 44px floor in the area. A workspace's page keeps its lock control last under "Access" with a confirm that names the workspace, and links into the ledger; a user's page opens with every state as a badge (operator, suspended, sign-in blocked), the sentences after, and the controls in one row, with a confirm that names the person; the users search renders a hit as a list row with the address and a miss with a link into the ledger; the roster shows addresses and stacks at phone width. Ledger row details link to the person's page and to "only this workspace", the pivots say what they narrow, and every control that navigates the whole page (sort, rows, pager, range preset, pivot, Clear) returns focus to itself — or to the choice just made — via `data-focus-key` in `navigation_focus.js`. `UI::ListGroup` and the activity feed's list carry `role="list"`; `shared/_empty_state` is one hairline and its action link a 44px target. (modelrails_ui #201, #204)
- The first-run wizard's invite step is labelled "Invite" and headed "Invite people", and its email box carries the members page's hint instead of two example addresses, so a fork whose project noun is "team" no longer reads Course · Team · Tools · Team. (#1147)
- Docs: QA flow 9 walks the operations area end to end (#1139); every bracketed rake command in the developer docs is quoted, because zsh globs `task[arg]` and never reaches Rails; the forking guide names the two invariants that read `.fork.yml` and says `bin/setup` leaves the git hooks to `bundle exec lefthook install`.
- The vocabulary gates teach when they fail. Each of the three code-smell specs behind `config/vocabulary.local.yml` now says what went wrong, why it matters (a renamed product shows the old word; a JS-filled key raises), the corrected line, the escape hatch, and the doc link; the bare-noun gate lists the placeholders from `Vocabulary.tokens` rather than by hand, no longer calls a fork's own locale file "upstream-owned", and the spec-copy gate derives its nouns from `Vocabulary::NOUNS`. The forking guide and `bin/fork`'s TODO now say the rule covers a fork's own locale files too.
- Vendored UI components carry a three-line doc pointer instead of header prose; the reference is the modelrails_ui gem's `docs/components/<name>.md` (0.16.0), guarded by a code-smell spec.
- Workspace identity is one control. The current workspace's logo, name and the viewer's role head the sidebar on every workspace page — solo users included — and opening it lists the other workspaces plus "All workspaces"; the "You're in …" context banner is gone. On phones the same control sits above the Overview / Projects / Settings tabs, showing the five most recently accessed workspaces with "All workspaces" as the overflow. The workspaces index keeps the control in an "All workspaces" state: on a phone it names the signed-in user, so the page opens with the same identity anchor desktop shows above the heading. (#1078, #1089, #1093)
- The five cleanup and retention sweeps (unattached blobs, expired sessions, WebAuthn challenges, activity-log retention, notification cleanup) run on the `low` queue, set in both `config/recurring.yml` and each job's `queue_as`, so an ad-hoc `perform_later` routes where the schedule does; the two `workspace_*` notifier sweeps stay on `default` (#894).
- `Workspace::NotAdmittableError`, `AlreadyMember`, and `AtCapacity` descend from a new `Workspace::AdmissionError`, so a fork's `rescue_from` has one class to name; `HomeWorkspaceProtectedError` is a lifecycle guard and deliberately not a subclass (#689).
- No app-owned `t()` call carries an inline `default:` any more (26 sites; the vendored `app/components/ui` primitives keep the fallbacks the modelrails_ui gem ships with). Keys added: `markdowndocs.{search_placeholder,search_label,no_search_results,try_different_search}`. Keys removed as unused: `workspaces.index.row.role.*` (the workspaces row shows `role.name`, as every other role display does) and `notifications.index.retention_hint.days` (every value in `NotificationPreferences::ALLOWED_RETENTION_DAYS` has a `retention_options` label, and a request example now proves it). `AccountActivityHelper#account_activity_label` and `Authentication.display_name_for` no longer humanize a missing key either; `spec/code_smells/dynamic_i18n_keys_have_values_spec.rb` proves every `ActivityLog::SECURITY_ACTIONS` member and every configured provider has its label. `ProjectTools::Tool#name`/`#description` no longer humanize a missing key: `spec/code_smells/project_tools_have_locale_keys_spec.rb` fails for any registered tool without both keys, so a fork learns before deploy instead of shipping a humanized symbol. Prepares the `ModelRails/NoI18nDefault` cop.
- The ownership-transfer demotion's audit row names the owner stepping down as its actor (the membership's own user) instead of reading `Current.user`; from a controller the two are the same person, and from the console or a job the row now carries an actor where it carried `nil`. No model outside `Trackable` reads `Current` any more (#1008; playbook ruling 9).
- The pending-invitation unique index `index_invitations_on_email_and_invitable_pending` is replaced by `index_invitations_pending_live` (one unsuppressed pending invitation per email and invitable, any inviter) and `index_invitations_pending_ghosts` (one suppressed row per email, invitable and inviter). `db/schema.rb` conflicts on every fork sync, and a fork that names the old index breaks. `Invitation.bulk_invite!`'s `sent` counter still means *records created*: a first invite to a blocked address counts `sent` exactly as an unblocked one does, and a repeat invite that collides with the existing suppressed row counts `skipped`, exactly as an unblocked duplicate does — the symmetry is the point, since an asymmetric count would itself be readable as a block oracle.
- `modelrails_ui` is pinned at v0.15.1 — the calendar month-boundary and form-builder loaded-record fixes the app already vendors, now matching upstream; regenerate your per-checkout agent rules with `bin/rails g modelrails_ui:agent_rules`.
- The members page searches and sorts in Ruby (`WorkspaceRoster`) instead of SQL — names and email addresses are about to be encrypted at rest, and ciphertext cannot be `LIKE`d or ordered. Every row still loads as before; matching is now Unicode-aware. `Membership.search`, `Membership.sorted_by`, and `Invitation.sorted_by` are gone; a fork that called them chains `filter_by_role`/`filter_by_status` and hands the rows to the roster (#902).
- The test environment eager-loads unconditionally, exactly as CI does — previously `eager_load` was CI-only, so Zeitwerk load order (and every `descendants`/subscriber-registration side effect downstream) differed between the local pre-push gate and CI, and a green local run was not CI evidence. Costs a few seconds of boot per worker; a parity spec pins it. The full suite passed unchanged under eager loading — the gap was real but latent (#852).
- **Fork invariant — a failed audit write now fails the credential change it records.** Password set/change/removal and passkey enrollment/removal write their `ActivityLog` row in the same transaction as the mutation, with no rescue: for a credential event an unrecorded change is worse than a refused one. The visible consequence is a 500 on the credential action if the audit write fails, where previously it would have succeeded silently. Sign-in-from-new-device stays best-effort — the `Session` row is already the primary record. See [Architecture § Activity Tracking](/docs/developer/architecture) (#825).
- **Fork invariant — `Settings::PasswordsController#destroy` changed shape.** Password removal now runs as one transaction covering email-authentication teardown, the digest clear, and revocation of the user's other sessions, and uses `update!` rather than `update_columns` — so validations run on removal where they previously did not, and the audit row and notification now fire (they were silently skipped). A fork that overrode `#destroy`, or that relied on removal bypassing validation, inherits this on sync (#825).

- **Forks start AI-agnostic** — `.graphifyignore` (the last tracked AI-tool config) is untracked, and a template invariant now fails if any agent configuration (CLAUDE.md, `.claude/`, `.cursorrules`, …) is ever committed. AI tooling is a per-developer choice layered onto a fork, not something a fork inherits; the file disappears on your next sync and nothing depends on it.
- **The axe accessibility audit now runs everywhere and checks both themes.** It previously ran only under `ENV["CI"]` and audited whichever theme the example happened to leave behind, so the verdict depended on test choreography — the same command caught a violation on one run and missed it on the next, and a real dark-mode contrast bug reached `main` under a green CI. Both themes are now set explicitly, and the hook runs locally too (`SKIP_AXE=1` opts out for a focused loop). A fork may see AAA violations that previously surfaced only by luck (#541).
- **Security:** Raised the `rails` Gemfile floor to `>= 8.1.3.1` for CVE-2026-66066 — Active Storage did not disable libvips's unfuzzed image loaders, so a crafted upload could read arbitrary server files including `secret_key_base` (GHSA-xr9x-r78c-5hrm). #531 bumped the lock; the floor is what stops a fork's fresh resolve landing back on a vulnerable release, and a template invariant now fails if the requirement ever admits one.
- Replaced Playwright/Node with Cuprite (pure-Ruby CDP) for system specs, and swapped npm-based linters for Ruby gems (`erb_lint`, `mdl`) — the template no longer requires Node at all (#497).
- Bumped Ruby to 4.0.6 (#501).
- Bumped SimpleCov to 1.0.2 (major). `SimpleCov.running` was removed; the coverage-config spec now asserts stdlib `Coverage.running?` instead. 1.0 also absorbs `simplecov-html`, `simplecov_json_formatter` and `docile`, so those drop out of the lockfile — HTML reports and `SimpleCov.collate`'s merged-resultset floor are unaffected. A fork with its own coverage spec will hit the same removal.
- Bumped `active_storage_validations` to 4.0.0 (major, #560) — it governs the avatar/logo upload allowlists (`content_type`/`size`); forks with custom validators or matchers should skim its 4.0 changelog for API changes. `solid_queue` moved to 1.6.0 (#559).
- **Locale keys moved** — forks that overrode any of these need to move their override: `invitation_accepts.create.invalid_token` → `invitation_accepts.invalid_token`, `invitation_accepts.create.expired_or_used` → `invitation_accepts.expired_or_used`, `invitation_declines.create.invalid` → `invitation_declines.invalid`. They are emitted by a filter shared across two actions, so they now sit at controller scope. An override left at the old key silently reverts to upstream English.
- `t(".key")` is now used only inside controller actions; private helpers use absolute keys, so `i18n-tasks` can verify them statically.
- **Floating overlays (menus, popovers, tooltips) render in the browser top layer and place via CSS anchor positioning** — no more clipping by `overflow:hidden` ancestors (#700, #701).
- **Forms render through `UI::FormBuilder`** — the gem's one-field-wrapper builder wired to `ActiveModel::Errors`; `TailwindFormBuilder` shrinks to the app-specific seam subclass (#718).
- **UI consolidation** — avatars, workspace icons and project logos render through `UI::Avatar` (#749); status pills through `UI::Badge` (#759); buttons on the `.btn-*` family with a new `.btn-outline` (#761); the docs breadcrumb through `UI::Breadcrumb` (#762).
- Vendored `modelrails_ui` adopted through v0.13.0 — ModalChrome modal family, soft/neutral badge, form-contract fix, `form_draft` lifecycle, `min-h-input` token, data hooks (#720, #721, #777, #780).
- **Sandi-review refactor arc** — named model rules (capacity, ownership, activity workspace), `OauthLink` PORO with a unified `PendingClaims` matrix, notification predicates + dedup DSL + one timezone rule, and controller silent-failure mechanics named and declared (#632, #634, #635, #636). Forks calling the old `Signupable` claim helpers (`accept_pending_join_link!` and kin) follow them to their new homes.
- **Comment audit** — stale, wrong and dead-pointer comments removed; essay comments relocated into developer docs; comment-compensated structure dissolved into named guards, locals and partials (#616–#622, #626).
- Project resolution has one home — the `ProjectScoped` controller concern (#631).
- Activity logs are retained 12 months by a sweep job — the trail is best-effort by design, so bounded retention is the honest guarantee; a regulated fork changes one named constant (and the comment names the other line that must change with it) (#612).
- Shipped data migrations are frozen (inline models, literal backfills) with a code-smell guard, and the CSP `form-action` list is derived from the OAuth provider registry instead of hand-maintained (#611).
- The tenancy lint now catches where-chained loads and scans helpers and views (#593); system specs fail on any runtime CSP violation, so a CSP block silently killing a feature is red on first run (#613).
- CI's test job is sharded across two free runners (#615).
- The docs truth pass — the extending guide's create example now teaches the atomic creation-verb shape instead of the pre-#660 two-write anti-pattern; ghost method pointers resolve again; the README describes the actual multi-tenant kit.
- Dependency bumps: mdl 0.18.1, image_processing 2.0.3, bootsnap 1.25.0, lexxy 0.9.29 (#586–#589); tailwind_merge 1.5.4 (#666), thruster 0.1.25 (#669), brakeman 8.0.6 (#671), GitHub-Actions group bumps (#668, #696). **axe-core-rspec 4.13.0** — the a11y gate's rule stack moves, so a previously green fork can newly fail AAA (#670). **SimpleCov 1.1.1** — forks with their own coverage config should skim its changelog; SimpleCov majors have broken this template's coverage spec before (#672).
- Invitation emails no longer name the workspace or project they are for. An invitee has agreed to nothing yet, so the subject line sitting in their inbox — and anyone they forward it to — no longer discloses a private group's name. The name appears once, on the accept-or-decline page the recipient chose to open. The inviter is identified by their verified address rather than a display name, which is attacker-chosen text (#815).
- `shared/_sortable_header` takes a `frame:` local instead of hard-coding the members frame; the vendored combobox controller dispatches `change` on its hidden input after a selection (port to modelrails_ui pending).

### Security

- Thruster 0.1.27; the image scan's accepted Go findings move to the three DoS CVEs in its go1.27.1 build (no fixed release exists), and the eight go1.26-era entries are retired (#1410).
- **Blocking an inviter needs the signed link from the invitee's own invitation email** ([#951](https://github.com/dschmura/modelrails_base/issues/951)). Every invitation email gains a "Don't invite me again" link (signed, seven-day, query-string token) that opens a confirmation page; its button declines and blocks and states the outcome on the page. The decline page's block dialog and the bearer `POST /invitations/:token/block` route are gone, so nobody holding only the invitation URL can block. The inviter still never learns a block exists. `Invitation` also lost its delivery-suppression cluster to `Invitation::Suppression` (the split #915 asked for). Fork owners: templates that rendered the old dialog show the hint instead; anything linking to the removed route needs the email link.
- **Workspace join links now expire seven days after creation or rotation.** Rotation also revokes an expired-but-unrevoked link, closing a `RecordNotUnique` on rotate. Fork note: every existing link expires one week after this migration runs unless rotated first — rotate from workspace settings ([#952](https://github.com/dschmura/modelrails_base/issues/952)).
- **The app's cookies are classified once, next to Biscuit's consent categories.** `session_id`, Rails' own session cookie, `biscuit_consent`, `theme`, and `sidebar_collapsed` are all `necessary` and need no consent gate; a spec ties the classification to the security doc so a new cookie can't land in only one of the two ([#714](https://github.com/dschmura/modelrails_base/issues/714)).
- **Invitation tokens are encrypted at rest, deterministically.** `invitations.token` and the parked copy on `authentications.pending_invitation_token` were the last bearer credentials stored plaintext; a fork owner must run the migration before reading old rows (`bin/rails db:migrate`), and it is re-runnable ([#953](https://github.com/dschmura/modelrails_base/issues/953)).
- **Bearer tokens in request-log paths are an accepted, documented exposure** ([#916](https://github.com/dschmura/modelrails_base/issues/916)). The security doc records the five flows, why Rails filtering cannot reach a path segment, that the proxy logs the path and query regardless, the host-only readership and 10 MB caps, each token's lifetime, and the triggers that reopen the decision; a code-smell fence holds the route set to that list so a new secret goes in the query string or the body. Four behavioural findings from the same review are tracked separately (#950–#954).
- **Email verification now requires a click, not just a network fetch, and connected-account verification moves its token out of the URL path.** Both verification flows split into a GET confirmation page that never verifies and a POST that does, so a mail scanner or link prefetcher can no longer silently confirm an address. Connected-account verification's token now travels as a query parameter, matching the magic-link and first-email shapes; a legacy path-token route stays live for one token lifetime (24 hours) past deploy so in-flight emails still land — fork owners with the old link format shared elsewhere have one day after deploy to treat it as spent (#950).
- **Magic-link sign-in now spends its token before checking for a matching user.** `POST /magic_link_callback/:token/sign_in` previously left the token unconsumed when no account matched the address, so it stayed replayable against a future signup for that same address; it is now consumed unconditionally before the user lookup (#954).
- `first_name`, `last_name`, and `company_name` are filtered from request logs and `#inspect`, alongside the `email` partial match Rails already ships.
- Password create, change and removal now share a rate limit (10 / 3 min), matching every sibling settings endpoint; each mutation writes an audit row retained under the security floor, so the endpoint has a durable side effect per request (#819).

- **A parked open-link join no longer force-joins a pre-existing account.** A logged-out visitor lured into an open-link join stashes the token in their session (Flow B), and it survives login. Previously, if the person who then authenticated turned out to be a *pre-existing* user — specifically one linking a new verified OAuth provider — they were silently added to the workspace as a side effect. Now only a brand-new account created in that same signup flow auto-joins (its signup is its consent); a pre-existing user instead sees a dismissible "You followed a link to join **X** — Join / Dismiss" banner and re-consents explicitly (`PendingJoinsController`, `Signupable#accept_pending_join_link!` gated on `newly_registered:`). Low severity (open-link only, visible, leaveable), but it removes the last silent-admit path.
- **Workspace join-link tokens are hashed at rest, and the link is show-once.** The open-link join token is now stored only as a SHA256 digest (mirroring the magic-link token) in both `workspace_join_links.token_digest` and the parked `authentications.pending_join_link_digest` — a database leak no longer hands over a working join capability. Because the plaintext can't be re-derived, the workspace-settings join section shows the full link **once**, right after you generate or rotate it (copy it then); afterwards it shows a masked stub and a Rotate action that mints a fresh link. The migration backfills digests from the still-present plaintext, so links already shared keep working across the deploy. Forks that customized `workspaces/settings/_join_policy_section` or read `WorkspaceJoinLink#token` directly will need to move to `#plaintext_token` (available only on create/rotate) and `.find_active`. Closes the tracked SEC-5 follow-up.
- **Magic-link tokens are hashed at rest, and sign-in is a POST (SEC-5).** The bearer token is now stored only as a SHA256 digest — the plaintext lives solely in the emailed URL — so a database leak (backup, replica, log, SQLi) no longer hands over live logins. And clicking a magic link now lands on a "Sign in as x@y?" confirmation page whose button POSTs to complete sign-in: a bare GET from a mail scanner, link unfurler, or prefetcher can no longer burn the token or establish a session. The migration backfills digests from the still-present plaintext, so in-flight links keep working across the deploy. Forks that customized the magic-link callback view or routes will feel the GET→POST split.
- **Session is reset at login (SEC-4).** `start_new_session_for` now `reset_session`s at the privilege boundary, dropping any leftover pre-auth session state and keeping only an explicit allow-list (`SESSION_KEYS_SURVIVING_LOGIN`: the post-login return path and the pending invitation/join tokens). This is defense-in-depth hygiene rather than a fixation fix — Rails' encrypted cookie store already prevents a forged session hash and the DB session row is rotated on every login. A fork that stashes its own pre-auth session key registers it in that constant.
- **Authorization is enforced at CI (SEC-3).** A new code-smell spec (`spec/code_smells/mutating_actions_are_authorized_spec.rb`) walks every mutating (POST/PATCH/PUT/DELETE) route and fails the suite if the action neither calls Pundit's `authorize` nor is on an explicit, reviewed allow-list (public auth flows + actions scoped to the current user's own resources). This puts teeth on the standing "all controllers must enforce authorization" rule without a runtime `verify_authorized` and its skip-list drift: a fork contributor who adds a mutating action to a tenant resource and forgets `authorize` gets a red test, not a silent IDOR. The detector keys on a real `authorize`/`authorize!` call (not `authorize_*` helpers or comments) and has its own failing-fixture self-tests.
- **Re-authentication for sensitive account changes (SEC-2b).** Changing or removing your password, enrolling or deleting a passkey, changing your email, or unlinking an OAuth account now requires a recent "confirm it's you" — so a borrowed session cookie can't be converted into a permanent takeover. Confirmation uses whatever factor you have: your password, a passkey (bound to your account — someone else's passkey can't confirm your session), or a one-time code emailed and entered in-page. The window is 15 minutes, tunable in `config/initializers/sessions.rb`, where `reauth_enabled` also turns the whole feature off for forks that don't want the friction. **This also fixes a real bug:** email changes were gated on having a password, so passwordless (magic-link / OAuth) users could never change their email — that gate is now re-authentication, which every user can satisfy.
- **Sessions now expire (SEC-2a).** Previously a session was valid forever (a 20-year `permanent` cookie, no server-side lifetime), so a stolen cookie never went stale. Sessions are now signed out after an idle window (default 30 days) or an absolute lifetime (default 90 days) — both tunable in `config/initializers/sessions.rb` — enforced fail-closed at request time, with an announced "your session has ended" flash rather than a silent bounce to sign-in. `last_active_at` is refreshed off the SQLite writer-lock hot path via an in-memory throttle. Expired rows are swept daily (`ExpiredSessionsSweepJob`). Changing or removing your password now signs out every *other* device. **Rollout:** existing sessions get a fresh idle window on deploy (they are not retroactively expired); sessions older than the absolute timeout will be signed out. Forks that customized `Authenticatable#start_new_session_for` / `find_session_by_cookie` should expect a merge here.
- **Role grants are permission-gated (SEC-1).** An actor may grant or assign a workspace role only if they already hold every permission it confers — closing an Admin→Owner privilege-escalation path where an admin could promote a member, mint an invitation or magic link, or reactivate a deactivated owner, and inherit `manage_workspace`. Enforced server-side in `ApplicationPolicy#may_grant?` across member role changes, reactivations, email and magic-link invitations, and onboarding invites; role pickers render only assignable roles as defence-in-depth. `MembershipPolicy#update?`/`#reactivate?` additionally refuse to manage a membership whose role the actor couldn't grant, so an Admin can no longer edit or restore an Owner's row. Invitation acceptance (`Workspace#admit`) stays safe because the role is gated at invitation-creation time, not at redemption. Role changes are now recorded in the admin-only activity feed with the role slugs by value (not the mutable `role_id`). See [Extending](/docs/developer/extending) and [Workspace Administration](/docs/user/workspaces).
- Magic-link sends are recipient-throttled across every send path (SEC-9, #584); `workspaces#update` and `avatars#destroy` are rate-limited (#585).
- `Project#logo` uploads validate content type and size (SEC-8, #590).
- Global error handlers filter the referer through `url_from` — no open-redirect via a crafted Referer (SEC-10, #591).
- cropperjs is vendored; jsdelivr is dropped from the non-development CSP (SEC-6, #594).
- Action Text direct uploads are authenticated and gated (SEC-7, #595).
- Audit-trail gaps closed: blocked role escalations are logged, `membership.created` records the role and `granted_by`, and the ownership-transfer demote is audited (SEC-1 follow-up, #597); project-invite memberships record `granted_by` via `Workspace#admit` adoption (#629).
- Documented that account lockout scopes to password sign-in only, by design (SEC-12, #592).
- sqlite3 bumped to 2.9.6 for GHSA-mwm8-39rw-8826 (#599).
- CI/workflow hardening — the Dependabot-checksums job checks out the exact SHA the author gate evaluated (TOCTOU), a shard secret race is closed, and a throttle-store leak is fixed (#783).
- A single invitation submission is capped at 20 addresses. The controller's rate limit bounded how often someone could submit; nothing bounded how far one submission could fan out. The cap is never applied silently — mid-flow the invitations that fit are sent and the remainder reported, and during first-run onboarding the submission is refused so the list can be trimmed rather than half-processed.
- **An email authentication's `uid` is the user's id, not a second copy of their address** ([#903](https://github.com/dschmura/modelrails_base/issues/903)). Both columns are deterministically encrypted, so they held identical bytes for the same address and a leaked dump joined them. `Authentication` now assigns the value itself; the three writers that kept the mirror by hand are gone, including the `update_all` that skipped the `uid` uniqueness validator. Fork owners: run `bin/rails db:migrate` to rewrite existing rows, and drop any `uid:` you pass when creating an email authentication.

### Fixed

- The "Confirm it's you" page offers "Send a new code" beside Confirm and says where the code went and how long it lasts, and its code-entry state is derived from a live `ReauthenticationChallenge` rather than a session flag, so an expired code returns the page to offering a fresh one instead of stranding the user on a field that can no longer work. The "Choose how to confirm" heading and the divider above the email factor render only when there is more than one factor to choose between.
- A fork's first CI run no longer fails the invariant that checks `bin/fork`'s rename targets still exist upstream: it skips when `.fork.yml` is present, the way the placeholder-address check switches on. Before this every fork was red on that example whatever it pushed. (#1152)
- A project's "Add member" button opens the new-membership form instead of reloading the members list it sits on. (#1155)
- `operators:grant` vouches for the address it was given (a verified email authentication, create-only, as the `:shared` seed does), so a console-minted operator can send invitations without a verification round trip an invite-only instance has no mail for. (#1146)
- Joining a workspace is onboarding: `Workspace#admit`, the one membership-grant seam, stamps `onboarded_at`, so an invitee or link-joiner under the `none` preset never lands in the first-run wizard, and a refusal inside the wizard leaves it instead of looping. (#1145)
- An expired lockout resets the failed-attempt counter, so the next wrong password starts a fresh count instead of relocking at once. (#1140)
- Static rows on the workspaces, projects and resources indexes no longer highlight on hover (`text-interactive` on the sunken hover surface is 6.85:1, under AAA), and the resources index's title link meets the 44px target floor; that page gets its first axe audit. (#1141)
- Activity rows name who joined instead of "System": `ActivityLog#display_subject` falls back to the membership's member for `membership.created` rows written with no actor (a first signup's `after_create` runs before `Current.user` exists), and a workspace's own rows are attributed to the workspace via `Workspace#activity_workspace`. `invitation.updated` rows render again. (#1087)
- A spent magic link re-presented by its signed-in owner is answered truthfully — "you're already signed in" on a sign-in link, the registration confirmation on a signup link — instead of "expired". `GET` never consumes a token; the replay check is a predicate on the spent token and is fenced to the same address. (#1088)
- The workspace Profile page's Save button sat outside its own form because the logo section was nested inside it; the logo section is now a sibling of the name form. (#1079)
- The interpolation that carries a workspace's name is spelled `%{workspace_name}` everywhere (39 locale strings, the mailer templates, the join flow and their specs); `settings.en.yml` already used the long form, and the short one was a homonym of the domain noun that a vocabulary seam could silently fill. The name token is `%{workspace_name}` by convention and by the vocabulary gates (the seam above), not by a per-token spec. The i18n guide no longer claims the unused-keys check is ungated (#1108).
- The brand mark is a fork seam. `app/views/shared/_site_mark.html.erb` is a file that is one `<svg>` and nothing else, `merge=ours` like the brand words and colors, so a fork replaces it wholesale and never conflicts on it again; the favicon and PWA icon set in `public/` are `merge=ours` too. `_site_logo` is now just the lockup — mark and name as siblings, no wrapper — and the caller's link sizes the mark with `[&>svg]:h-*`; the `size`, `show_name`, and `color_class` locals are gone (no caller ever set the last, and only `name_class: "sr-only"` was ever varied). Two view specs assert the mark's contract and the lockup's shape; the extending guide's table, which had documented raw palette defaults since March, is rewritten, and the forking guide and `bin/fork`'s TODO list name the artwork (#1104).
- Every workflow job declares `timeout-minutes` (5–20, sized to each job's real duration), and the three `apt-get` steps carry a 5-minute step budget, so a runner-side hang fails in minutes instead of holding the required status for GitHub's 360-minute default; a template invariant keeps it that way (#1101).
- A notification whose delivery job never got enqueued is recovered instead of lost: noticed enqueues `Noticed::EventJob` after its own transaction commits, so a failed enqueue left committed rows and a burned idempotency key with no email or broadcast behind them. `noticed_events.dispatched_at` is stamped when the job starts, and `NotificationDispatchReconcileJob` (every 15 minutes, `default` queue) re-enqueues anything still unstamped between five minutes and 24 hours old, stamping each row as it goes so a backed-up queue cannot produce a duplicate fan-out. The migration backfills existing rows with their own `created_at` — a fork that skips it re-delivers its entire notification history on the first sweep (#927).
- `clear_solid_queue_finished_jobs` could never be claimed: the entry carried no `queue:` key, so Solid Queue routed it to `solid_queue_recurring`, which no worker in `config/queue.yml` polls. Every fork inherited the dead job — `config/recurring.yml` is not a `merge=ours` path (#894).
- **The WCAG 2.2 AAA teardown audit is live again and cannot be switched off silently.** A redundant session reset had left it skipping every system example; an after-suite gate now fails the run for any navigating example it did not audit, a code-smell fence refuses the ways of disabling it, and the 17 real violations it had been hiding (identity-picker file input without a label, 17px error-summary links, a status element inside a listbox, 30–36px menu-panel links) are fixed in markup. ([#912](https://github.com/dschmura/modelrails_base/issues/912))
- Membership notification callbacks are best-effort: a raising role-change, add, re-admit, or self-join notifier no longer 500s a committed membership — it reports and moves on, matching the removal notifier's existing posture (#935).
- Removing a member is idempotent: a replayed DELETE on an already-removed membership no longer re-stamps the removal timestamp, no longer writes a second audit row, and no longer sends the removed member a second notification and email.
- The workspace activity feed renders its written English again — every key under `activity.actions` was flat and dotted, which I18n's nested lookup never finds, so each row silently degraded to a humanized column value (#911).
- A membership removal reads as "Ada deactivated Dee" and a re-admission as "Ada reactivated Dee" instead of both claiming "had their role changed" — and instead of naming the person who acted as the person removed, which the passive voice did. A member who removes their own membership "left the workspace". `ActivityLog#display_action` picks the sentence from the row's own changes and its actor, and a row carrying both a role and a status change reports the status (#932).
- A removed member who still holds a workspace URL now lands on the workspace index with a not-found notice instead of an endless redirect: `User#workspaces` runs through kept memberships only, and the not-authorized handler refuses to answer a refusal at the workspace's own path with that same path (#931).
- `normalizes` is the one home of email normalization: `Invitation`, `MagicLinkToken`, and `Authentication` now normalize `email` the way `User` does (NFC, strip, downcase, punycoded domain), and the eight hand-rolled `downcase`/`strip` copies in controllers and models are gone. An existing member whose address has an internationalized domain could be re-invited — the bulk-invite dedupe compared a bare `downcase` against punycoded storage.
- Calendar arrow keys cross the month boundary instead of dead-ending at the grid's edge — a target past the 42-cell grid pages to the adjacent month and lands on that date (APG date-grid). The date-picker keyboard spec no longer depends on the day it runs; it failed on the last days of every month.
- `modelrails_ui` is re-pinned to v0.14.0 — a Dependabot PR moved the `Gemfile` git-tag pin backward to v0.13.1, undoing the deliberate adoption in #803 (shared keyboard module, dark-mode `bg-hue-initials` AAA contrast, a `command` `<hr>` axe-critical fix, `dialog` focus-restore-on-disconnect, a `FormBuilder` object-less-form guard). No shipped behavior regressed — the gem is `group :development` only and every fix already lives in this repo's vendored `app/components/ui/`, `app/form_builders/`, and `app/javascript/controllers/` files — but the next `rails g modelrails_ui:add`/`:update` would have silently scaffolded from the older templates.
- The Stimulus readiness barrier now runs after every system-spec `visit` instead of an allow-list of two paths — the allow-list left ~536 visits across 164 files racing controller boot, which surfaced as intermittent "found 1 time including non-visible text" failures on loaded CI shards whenever an assertion read an element before its controller had touched it. A page with no controllers is treated as ready (so a redirect target or error page can't burn the budget and raise), a still-parsing document is not, and a harness self-test pins all three properties (#837).
- Axe audits are memoized per example on page state + options — a `axe_clean_in_both_themes?` call site used to pay six audits (check, eagerly built failure message, after-hook) on identical state; redundant passes are now free while any DOM change, theme flip, or option change still audits fresh, cutting the system lane's aggregate worker time by 23% (1029s → 792s) with coverage pinned unchanged by a harness self-test. The two cross-cutting after-hooks (axe, CSP) are now documented as the first thing to rule out when triaging a system-spec failure (#855).
- Runtime CSP-violation capture now covers every system example — the listener install was memoized on the long-lived browser while the page-scoped init script died with each example's session reset, so only the first example per worker process was actually listening; the install is now per-example, and a harness self-test proves the listener survives a reset (#848).
- Setting a first password commits the password and its email authentication atomically — a failure between the two no longer strands a password without its sign-in method — and the existing email authentication is found by provider rather than by an address that may have changed underneath it, which previously answered a legitimate password set with a validation error (#821, #865).
- The OmniAuth test cleanup now restores the pristine `mock_auth` snapshot instead of niling every key — the shipped `:default` AuthHash used to vanish for the rest of the worker process after the first OmniAuth example, making later examples order-dependent; eleven per-file cleanup blocks with the same destroy pattern are gone, and a hygiene spec pins the contract (#851).
- The demotion-while-viewing system spec now waits on the broadcast landing (the member's own role cell re-rendering) instead of racing a 5-second absence timeout against the commit → Solid Cable → WebSocket → morph round trip, which intermittently failed pre-push runs on unrelated work under the 18-worker suite (#841).
- Ten system-spec absence assertions are now anchored — each visited a page and asserted only absence, so a 500, a redirect, or a blank page kept them green (one guarded whether destructive workspace controls stay hidden). Each now first asserts something the intended page must render, and a new code-smell guard fails any future post-navigation negation that lacks such an anchor (#853).
- Five waits that named a duration instead of a condition: the three form-draft negative-assertion windows share one helper-owned budget with an honest contended-box margin (the old 0.5s left 200ms over a 300ms debounce plus async crypto), the toggle-knob poll runs on the suite-owned Capybara budget and reports through its own message instead of a bare `Timeout::Error`, and the toast auto-dismiss wait is derived from the toast's own configured timeout + stagger instead of a guessed 18-second ceiling (#857).
- Password removal no longer fails when the account is invalid for reasons unrelated to credentials (an attachment allowlist tightening, say) — removal skips full-record validation while the audit row and removal notification still fire (#820).
- The `:authentication` factory no longer draws uids from a bare PRNG against the unique `(provider, uid)` index — the email provider's uid now mirrors its user's address as production does, OAuth uids carry sequence prefixes, and factory contracts pin both, closing #456's collision class at its source (#856).

- Demoting the last Owner through the role picker is now refused (previously only deactivation was guarded) — `Membership#change_role!` runs an owner-floor check inside the same locked transaction and rolls back, surfacing "You can't demote the last owner. Transfer ownership or promote another owner first." The error is delivered as a toast so it survives the inline-edit Turbo Frame.
- Four craft defects in the audit-trail specs: two assertions that no code path could fail are deleted, the retention-sweep spec materializes its user outside the time warp so onboarding rows keep real timestamps, and a factory `:security` trait — contract-pinned against `record_security_event!`'s real output — replaces twelve hand-rolled copies of the security row shape (#830).
- Avatars and workspace logos accept **HEIC/HEIF** — the iPhone camera default, previously rejected, which bounced the most common source of a phone upload. The allowlist had been set to `web_image_content_types` (what a browser renders) rather than what the app can safely process; Rails already converts the variant to PNG. Safe under the post-CVE-2026-66066 posture: both formats load and transform under `Vips.block_untrusted(true)` and remain in `variable_content_types`. Forks that narrowed this list should widen it too.

- The membership last-accessed touch is proven by a request spec instead of a browser session — the touch is a controller concern's single `UPDATE`, so the system spec bought nothing for ~176× the cost; assertions carried over unchanged plus the response status the browser version never checked. First worked example of the #854 system-lane migration (#854 stays open).
- The device-list spec on Active devices scopes to `data-testid="device-list"` instead of `ul[role='list']` — a selector unique only by accident, whose ambiguity pressure once cost a new list its accessible `role="list"` attribute; the test is now strengthened rather than the markup weakened (#818).
- Devcontainer installs Chromium for Cuprite system specs — #502 removed the old `npx playwright install` browser step without a replacement, leaving the `ruby:slim`-based devcontainer with no browser to drive, so every system spec failed there; ferrum now auto-detects the apt-installed `chromium`. A template-invariant spec guards that a browser is installed and that Node stays out of `.devcontainer/`.
- The template no longer ships a real support email address to every fork — the default is a placeholder forks set to their own address (#549). **Forks created before this change never receive it**: `pages.en.yml` is fork-owned (`merge=ours`), so the fix does not arrive on sync — audit with `git grep -n "modelrails.dev" config/locales` and replace any hit with your own address. This is the worked example of silently-missed upstream fixes in [Forking](/docs/developer/forking).
- Toast containers are named region landmarks — clears the app-wide aria-prohibited-attr axe violation and keeps toast content inside a landmark.
- **Security:** CSP nonce generator returned blank on a visitor's first request (no session yet), emitting an invalid `'nonce-'` source that blocked every inline script — Stimulus never booted for first-time visitors (#499).
- Cookie-consent banner (biscuit-rails): reject is now the emphasized default action (not accept), the banner no longer flashes visible before JS hides it, and reopening the preferences panel shows the visitor's actual saved choices instead of stale checkboxes (#500).
- **Notification bell returned a 500 in production for any user whose saved locale was not `en`.** `I18n.available_locales` was derived from the load path, so `faker` (development/test only, ~350 locale files) made it ~60 entries under test and `[:en]` in production — the notifier specs passed while the same code raised `I18n::InvalidLocale` for real users. `config.i18n.available_locales` is now pinned in `config/application.rb`, `UserPreferences#locale` validates against it, and `recipient_locale` falls back to the default for rows written before the validation existed.
- Six locale keys that silently rendered `translation missing` to users — the flash after saving notification preferences, the invalid/expired flashes on the invitation accept and decline pages, and an Invitation validation message. Enabling `config.i18n.raise_on_missing_translations` in test surfaced all of them; the invitation flashes were defined only under `create` while a shared filter also served `show`.
- Digest email's per-notification link read from a `notifications.bell.see_all` key that never existed, falling back to an inline default.
- **Project creation is atomic** — project INSERT and creator membership commit or roll back together via `Workspace#create_project`; a failed membership insert no longer strands a committed project that is invisible to its own creator and permanently consumes a capacity slot (#660).
- **Combobox ArrowUp with no active option enters at the last option**, per the APG keyboard contract (#673).
- **Write-path integrity** — the pwned-password check runs before the write transaction with bounded HIBP timeouts (an outbound HTTP call inside the SQLite write lock was an externally-triggerable app-wide write stall), invitation decline/revoke/resend adopt `accept!`'s guarded transaction shape, and workspace creation is atomic via `Workspace.create_owned` — the #660 bug class, closed for its twin (#782).
- Tenant-query correctness and REST honesty — the project activity feed rides an indexed `ActivityLog.for_project` scope instead of scanning the global table, `ProjectPolicy::Scope` ends the listed-but-bounced project rows, notification-open and project-pin become idempotent noun routes (forks linking the old `GET :open` / `PATCH :toggle_pin` paths must move), and Stimulus controllers lazy-load (#784).
- Seven shipped accessibility violations the audit was blind to — post-navigation focus lands on the main landmark, the consent-banner exclusion is retired, keyboard contracts and honest live announcements (#610).
- Header workspace switcher rendered a blank chip after a fresh login — it now falls back to the most-recently-accessed workspace (#776).
- Landing CTAs adapt for signed-in visitors instead of dead-looping into the sign-in redirect (#779).
- Menu-family keyboard entry — panel-focus ArrowUp guard, and the combobox reopens on zero-filter (#781).
- Three responsive defects — members table clip, project nav overflow, toggle label collision (#741).
- Resource forms go through `UI::FormBuilder`, so server-rendered errors replace browser validation bubbles (#748).
- "Active devices" renders inside the settings shell instead of a bare page (#723).
- Component fixes: every instance gets its own element ids (#704); a submenu left open by its parent and an avatar lost after a swap (#707); avatar fallback when the image fails before the controller connects (#708); `trigger_class` merges over the a11y floor instead of replacing it (#709).
- Panel-checkpoint blockers: avatar recovery hue and card-scoped spec integrity (#750); target-floor parity, a suite-wide phantom-class guard, and the outline rename (#775).
- The invitations sort control sorts by the key it displays (#613).
- Notifier recipient resolution no longer N+1s on preferences (#630).
- Deployment docs' SSL section matches the shipped config and documents the green-healthcheck/dead-app trap (#600).
- The quiet-hours "no days selected" warning is now rendered by the server rather than revealed by JavaScript after boot — a user whose JS was slow or blocked saw no warning at all in the one state it exists for.
- **Email digests key off read state, not a separate `seen_at`.** A digest could re-send items you had already read, and could drop items that arrived while it was assembling; it now selects unread items over a half-open window, re-checks they are still unread at delivery, and stamps the window it actually covered. Security notifications are excluded from digests entirely — they are the ones you want immediately (#814).
- **The magic-link sign-in race is gone from the eleven specs that still hand-rolled it.** Each drove the app into minting a token and then minted a second, competing for the one live-token slot a partial unique index allows — #846's shape, at fourteen sites. Setup now goes through `sign_in_via_form`; the specs that are *about* the magic link keep the form and read the token out of the mail the app sent, which also proves for the first time that the emailed link works. A code-smell spec fails the suite if the two-writer shape returns (#849).

## v2.0.0 — Passwordless Auth, Workspace Lifecycle & Navigation IA (2026-07-06)

### Breaking

- Git history rewritten to purge the internal root `docs/` directory (now the separate [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) repo) — every commit SHA changed; existing clones and forks must re-sync (`git fetch && git reset --hard origin/main`).
- `config/deploy.yml` `servers.web` moved from a flat host list to a `hosts:` + `options:` structure for `max-replicas: 1`; forks that customized it must migrate — see `app/docs/deployment.md` (#135).
- Email verification switched to signed, stateless tokens; dropped the `verification_token`/`verification_sent_at` columns — links issued before upgrade stop working (#178).

### Added

- Workspaces index client-side filter + denser cards — the filter appears once the "Other workspaces" list is long enough to scan; each card sets the logo beside the name with a single metadata line (#428).
- Persistent workspace-identity bar anchoring the workspace shell, with tightened content spacing (#423).
- Workspace & project lifecycle — Archive (reversible; restore from the Archived section) and permanent Delete (workspace deletion gated by a type-the-name confirmation), cascading workspace → projects (#413, #414).
- Operator workspace lock — `rails "workspaces:suspend[slug]"` / `"workspaces:unsuspend[slug]"` puts a workspace on hold ("This workspace is locked."), blocking owners until released (#415).
- Passwordless-first sign-in — magic link is the default; a password is an opt-in set from Security settings (#374).
- Passkeys / WebAuthn — register platform authenticators and sign in with a discoverable credential (#375, #376).
- Browser-hosted GitHub Codespace — one-click cloud dev environment; boots, signs in, and runs the suite in-container (#385).
- Customizable Select picker — native `<select>` styled via `appearance: base-select` where supported, with an untouched native fallback elsewhere (#399, #402).
- `/docs` split into user and developer audience modes with an always-visible audience switcher (#381, #382).
- Per-project tools — extensible registry, per-project toggle, project-home tabs, and a self-hiding onboarding step (#364).
- First-run onboarding journey (`:none`) — name workspace → first project → invite, with a soft email-verification gate (#362, #363).
- `ClientAccess` model — scopes an external client to one project without a workspace membership or seat (#365).
- Per-project Clientside toggle, per-resource "share with client side" flag, and a read-only `Clientside::` area (#366).
- Client invite flow — `Invitation` client variant, `InvitationMailer#invite_client`, and client-only home routing (#367).
- `:none` onboarding posture (`WORKSPACE_ON_SIGNUP=none`) — signup creates no workspace; forks override `authenticated_home_path` (#343).
- Fork-owned brand-color seam `_brand.css` (`merge=ours`) — swap the primary palette without merge conflicts (#313).
- Deployment docs — Thruster X-Sendfile offload with a "don't set `x_sendfile_header`" guard, plus a health-check-timeout entry.
- `bin/deploy-guide` — target-aware deployment guidance (kamal / self-host / managed) plus a "without Kamal" contract section.
- Lookbook component explorer at `/lookbook` (development-only) for the vendored `UI::*` components.
- Vendored `UI::*` ViewComponents via the dev-only `modelrails_ui` gem; the form builder, `_modal`, and `avatar_for` delegate with no output change.
- Appearance destination time-zone picker — explicit `override=true` preserves the choice against the browser beacon (#154).
- Settings hub destinations — disambiguated H1s/descriptions, a shared page-header partial, and an Appearance page (#150).
- Settings hub mobile drawer — off-canvas sidebar below 768px with focus trap + ESC/click-outside dismiss (#148).
- Settings hub shell — sidebar-equipped `settings.html.erb` with context-adaptive, Pundit-gated items and Turbo morph.
- Personal-workspace OKLCH context ramp — desaturated slate via `[data-workspace-kind="personal"]`.
- Chroma-boosted workspace color swatch in the sidebar switcher.
- Notifications v1 — in-app bell + triage page, real-time broadcasts, preferences UI, email digests, and 10 notifier types (#48, #53–#56, #64–#71).
- Optional VS Code Dev Container matching the production image (#129).
- `.env.example` documenting required environment variables (#129).
- YJIT enabled in production (#129).
- CI builds the production Docker image on every PR (#134).
- Deployment, background-jobs, and dev-environment docs at `/docs` (#136).
- Clear "invitation was for a different email" notice on verification, signup, and accept (#177, #180).
- Single-tenant preset (`WORKSPACE_ON_SIGNUP=shared`) — one shared workspace, tenancy UI suppressed, env-driven seed.
- Per-workspace `join_policy` (`invite`/`open_link`) with a revocable `WorkspaceJoinLink`; both join flows wired; instance ceiling via `SIGNUP_PERMITTED_JOIN_STRATEGIES`.
- Fork seams — brand strings, `draw(:app)` product routes, extendable `/docs` categories, and `merge=ours` fork-owned paths.
- In-app forking guide at `/docs/forking`.

### Changed

- Workspace navigation IA — settings becomes a section of the workspace shell (Profile / Members / Limits under an active "Settings"), not a separate layout; drops the `settings_context` macro (#425).
- Mobile menu restructured — account actions first, workspaces below (recency-ordered, capped, with an "All workspaces" overflow) (#426).
- Mobile section-nav strip — in-page secondary nav replacing the header-accordion sub-nav hoist (#422).
- Email-first sign-in — one email field routes to password, magic link, or passkey; the connected-accounts page reflects real linked state (#377).
- Retired the deferred "personal workspace"/"personal profile" copy → "your workspace"/"your profile"; section label "Account" → "You" (honest-naming).
- Removed the half-wired dynamic-PWA scaffold; the static `public/manifest.webmanifest` stays (#306).
- Fork-readiness code-quality cleanup — duck-typed project resolution, narrower rescues, named activity-log records (#305).
- `.env.example` documents every operator-settable ENV var, with a template invariant guarding against drift (#298).
- SQLite `journal_mode: wal` declared explicitly in `config/database.yml`, with the busy-handler behavior pinned by spec (#304).
- CI lint tooling version-pinned — markdownlint + herb-lint in `package.json` via `npx`; dropped brakeman `--ensure-latest` (#299).
- Unified the UI signal vocabulary to `info·success·warning·danger`; signal chips move to tinted surfaces, fixing the muddy warning badge.
- Avatar notification indicator restored as a severity dot (v2) — desktop on the avatar, mobile on the hamburger; standalone bell removed.
- Email/password signup defers invitation acceptance until the email is verified (#175).
- `TENANCY_ONBOARDING` renamed to `WORKSPACE_ON_SIGNUP` — reads honestly (the app is always multi-tenant).
- Sidebar skips the personal-only `memberships` eager-load unless onboarding is `:personal` (#344).
- Workspaces index rewritten from phonebook to workbench — pinned-current row, last-accessed sort, inline Switch/Leave; adds `memberships.last_accessed_at`.
- Mobile shell — the header expands accordion-style inline, replacing the off-canvas drawer (#148).
- Header workspace switcher hides personal workspaces; the Settings sidebar switcher is the explicit switch surface (#145).
- Account, Notification, Security, and Workspace settings destinations use the shared settings page header.
- Motion-safe sidebar transitions; `data-settings-context-kind` → `data-workspace-kind`; hover prefetch on settings/switcher links.
- Route consolidation — `workspaces#edit` serves Profile, `workspaces/settings#edit` narrows to Limits & Plan (Admin-visible via `ProfilePolicy`).
- Notifications bell is a standalone header affordance; the user menu collapses to an identity block + sign-out.
- Mobile-accordion sidebar contents flow inline via chrome-free `_*_sidebar_items` partials.
- Sidebar items gain a divider and a context-aware section label (`Account`/`Workspace`).
- Sidebar nav items gain Heroicons v1 outline icons (8 new SVGs, auto-discovered).

### Removed

- `/me` ("Your home") — the workspace home consolidates to `/workspaces`, which gains an identity anchor (#429).
- Deprecated `invitations#index` redirect route + the redundant "Invitations" sidebar item — folded into the members surface (#398).
- `settings-drawer` Stimulus controller, `*.mobile_drawer.*` locales, and the off-canvas markup — superseded by the header accordion.
- `Workspaces::BrandingsController` + `/workspaces/:slug/branding/*` routes — identity picker moved to `WorkspacesController#identity_picker_hub`.
- `Workspaces::BrandingPolicy` — replaced by `Workspaces::ProfilePolicy`.
- Orphan header dropdown partials + the `navigation.new_workspace` locale — completes Path Y (the sidebar switcher is canonical).
- Header "Workspaces" text link + the `navigation.workspaces` locale — the sidebar switcher is the sole workspace affordance.

### Fixed

- Dev mail-preview location — `/letter_opener` (a Rails engine on the app), not the dead port 1080; corrected across the devcontainer, setup message, `/docs`, and the invariant spec (#431).
- `base-select` chevron layout + de-duplicated select labels (#421).
- Signups-closed sign-in view renders inside the turbo-frame instead of vanishing (#384).
- Codespaces boot — trixie `moby:false`, `bin/setup` (libssl-dev + Node), non-interactive Playwright, Solid Queue self-heal, and forwarded-proxy CSRF Origin (#386, #387, #388, #396, #397).
- Settings-hub Turbo morph is now actually active — `_layout_head` yields `:head` so the morph meta emits (#327).
- Single-tenant preset — invitation-driven signups adopt the invitation's role instead of a placeholder Member.
- Unauthenticated invitees can accept under invite-only signup — the accept page stashes the pending token (#345).
- Development mailer URLs follow the running `PORT` so letter_opener links work on non-default ports (#346).
- `Broadcastable` respects subclass `broadcast_events` overrides (destroys broadcast on `ProjectMembership`).
- Fixed the production `docker build` failure after the Ruby pin change (#132).

### Accessibility

- Alert severity icons (modelrails_ui v0.5.0) — a colour-blind-safe non-colour cue on info/success/warning/danger alerts; normalized warning triangle (#427).
- Quiet-hours warning sits in a stable `role="status"` wrapper so screen readers reliably announce it (#302).
- `autocomplete="off"` on the read-only join-link copy field, clearing the herb-lint warning (#299).
- WCAG 2.2 AAA contrast pass — six tokens bumped to 7:1; `text-muted` matches `text-body` (hierarchy via size/weight).
- axe-core CI promoted `wcag2aa` → `wcag2aaa`, with contrast-ratio/hex/font diagnostics in failures.
- Code blocks at `/docs` meet WCAG 2.2 AAA contrast in both themes (#137).

### Security

- New-member admission blocked into archived, deleted, or locked workspaces on every path — join links, invitations, signup claims, and the client area — with generic copy that never reveals which lifecycle state blocked an outsider (#417).
- Home workspaces (personal, and the shared instance workspace) can no longer be archived or deleted — a policy exemption plus a model guard that also covers console and direct-call paths (#417).
- Dependency CVE bumps — nokogiri/faraday (#371), css_parser 3.0.0/msgpack 1.8.3 (#400); unfixable thruster Go CVEs ignored in the image scan (#380, #395).
- Invitation acceptance bound to the invited email across every path and deferred until verified — a leaked link can't be redeemed by someone else (#175, #176).
- Per-recipient email throttle across senders — prevents N attackers from collectively flooding one inbox.
- Cross-user OAuth collision alert — a defense-in-depth email when someone tries to link your identity to another account.

### Maintenance

- `bundler-audit` runs in Lefthook pre-push, mirroring CI `scan_ruby` (#372).
- Bullet safelists consolidated into one shared source (`lib/bullet_safelists.rb`) so development and test can't drift (#403).
- `modelrails_ui` bumped to v0.4.0 (customizable-select); component previews de-flaked by dropping external CDN assets (#401, #373).
- Ruby bumped to 4.0.4 and enforced by Bundler across dev, CI, and production (#129).
- Production image no longer ships test gems (#129).
- Production deploys constrained to one web container with a longer job-drain window (#135, #130).
- Solid Queue uses named queues (`default`/`mailers`/`low`) (#135).
- Faster CI on native architectures via parallel bootsnap precompile (#131).
- IDN punycode normalization in `EmailNormalizer` for canonical email comparison.

## v1.4.0 — OAuth Hardening & Design System Primitives v2 (2026-04-28)

### Security

- Email normalization for storage and equality comparison now uses Unicode NFC + downcase + strip via a new `EmailNormalizer` module (`app/lib/email_normalizer.rb`). The `User` model's `normalizes :email_address` and `:pending_email` declarations route through it, so all `find_by` lookups and writes get canonical form (Rails 7.1 auto-applies normalizers to lookup values). The OAuth callback's "OAuth email matches user's primary email" check uses `EmailNormalizer.equivalent?` so an email like `café@example.com` matches itself across NFC vs NFD encodings — previously these would compare as different bytes despite being visually identical, forcing international users through email verification on every OAuth sign-in. Gravatar SHA-256 hashing also uses canonical form so the same email always produces the same Gravatar URL regardless of input encoding. IDN punycode conversion (e.g., `bücher.de` ↔ `xn--bcher-kva.de`) is NOT handled — explicitly deferred until a real interop concern surfaces; would require an addressable-style gem.
- `Authentication#generate_verification_token!` now retries up to 3 times on `ActiveRecord::RecordNotUnique` (defensive against the astronomically-unlikely 256-bit token collision). The `Account::ConnectedAccountsController#resend_verification` action also rescues `RecordNotUnique` at the request level — if every regenerated token still collides, users see a graceful "try again" alert instead of a 500 error.
- OAuth callbacks now check `auth_hash.info.email_verified` before auto-verifying or auto-linking. When an OAuth provider explicitly reports the email as unverified (Google's `info.email_verified: false` for unverified Google accounts), `OmniauthCallbacksController` no longer (a) auto-verifies a newly-linked authentication for a signed-in user even when the OAuth email matches the user's primary email, (b) auto-links a brand-new OAuth signup to an existing verified user account by email match, or (c) auto-verifies and signs in a fresh user from OAuth — instead, the new user is created with a pending authentication and a verification email is sent without signing them in. Closes the account-takeover surface where an attacker could create an unverified Google account using a victim's email and have the app auto-link the OAuth identity to the victim. Providers that don't expose `info.email_verified` (e.g., GitHub) are treated as implicitly verified — only an explicit `false` triggers the gate, preserving existing GitHub OAuth behavior.

### Added

- Design system primitives v2: semantic spacing tokens (`--space-section-gap`, `--space-row-padding`, `--space-action-group-gap`, `--form-input-height`) defined in `app/assets/tailwind/tokens/_spacing.css`. Tokens are CSS-var-only — never registered in `@theme` so they don't leak as Tailwind utility classes. Consumed inside `@layer components` rules and `TailwindFormBuilder` constants.
- Component utilities under a new `@layer components` block in `app/assets/tailwind/application.css`: `.btn-touch-target` (44×44 minimum, reads `--form-input-height`), `.btn-text` (font-weight/underline/focus-visible base), `.btn-text-danger` and `.btn-text-interactive` (color variants), `.action-group` (inline-flex with `--space-action-group-gap`).
- Layout utility `.page-container` (`max-w-2xl mx-auto px-4`) for narrow page wrappers — settings, account, and form-centric flows.
- `design-system.md` (now in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs)) — single-source reference for the spacing convention, semantic tokens, component utilities, class ordering convention, and migration recipe. Linked from README.md.

### Changed

- `app/views/sessions/email_error.html.erb` now uses `TailwindFormBuilder` via a new `EmailLookupForm` ActiveModel form object (`app/models/email_lookup_form.rb`). The view no longer hand-rolls form-input classes; the form builder auto-applies error styling, ARIA attributes (`aria-invalid`, `aria-describedby`, `role="alert"`), and inline error messages from the model's `errors` API. Validation is unified: blank email, missing email, and malformed email all surface the same `sessions.lookup.invalid_email` notice ("Please enter a valid email address."). Closes the v1.3.0 design-system debt note about this view bypassing the form builder.
- Refactored `app/views/account/connected_accounts/index.html.erb` to consume the new utilities (proof refactor — same visual output as before). Subtle visual change: the Resend button now inherits `font-medium` from `.btn-text`, matching Cancel and Disconnect. This unifies a pre-existing inconsistency where Resend was visually slightly lighter than the other text buttons.
- `TailwindFormBuilder` (`app/form_builders/tailwind_form_builder.rb`) now reads `--form-input-height` via `min-h-[var(--form-input-height)]` in three constants (`FIELD_BASE`, `SUBMIT_CLASSES`, `FILE_FIELD_CLASSES`) instead of hardcoded `min-h-[44px]`. Single source of truth for touch-target height across all form inputs, submit buttons, and file fields. Same 44px value, named source.
- `.btn-text` uses `focus-visible:` (not `focus:`) for the focus ring, matching the project's existing `.biscuit-btn` pattern. Focus rings now appear for keyboard navigation but not for mouse clicks.

### Fixed

- ERB lint job (`herb-lint`) now passes on `_a11y_sim.html.erb` after refactoring the dev-only mode-icons hash from `<% end,` syntax (rejected by herb-lint 0.9+'s `parser-no-errors` rule) to separate `capture do %>...<% end %>` assignments. Same compiled output, parser-friendly structure.
- CI test job now installs `libvips42t64` on the Ubuntu runner so Active Storage image variants generate without `LoadError`. Affected 9 identity-picker system specs that all failed with the same shared-library load error; root cause was missing system dependency, not test logic.
- Replaced the flaky `expect(page).not_to have_css("script")` assertion in the registration XSS-prevention spec with a deterministic raw-HTML byte check (`page.html.include?("<script>alert('xss')</script>")` plus a positive control on the escaped form). The original assertion depended on Capybara's visibility filter excluding hidden layout `<script>` tags, which Playwright sometimes computed inconsistently during page transitions.

---

## v1.3.0 — Verified OAuth Account Linking

### User-facing

- **Email verification for OAuth links with mismatched email.** When a signed-in user links a new OAuth provider whose email differs from their primary email, the linked authentication is created in pending state and a confirmation email is sent to the OAuth-returned address. The user must click the verification link before that sign-in method is active. Auto-verifies when the OAuth email matches the primary email (case-insensitive, whitespace-trimmed)
- **Pending state UI** on the connected accounts page: pending rows render in info-styled treatment with the email being confirmed, a help line ("Check your email…"), and dedicated **Resend confirmation** + **Cancel link** buttons. Verified rows keep the **Unlink** button (renamed from "Disconnect" for verb-pair consistency with "linked")
- **Post-OAuth confirming banner** appears once after the OAuth callback redirects back to connected accounts, calling out the email being confirmed and which provider is being linked
- **Provider display names** now render as "GitHub" (not the `titleize`-mangled "Github"), backed by an `Authentication.display_name_for` lookup used by every flash message, mailer subject, and view that names a provider
- **Token-based verify URL** at `GET /account/connected_accounts/verify/:token` works for both signed-in and signed-out users — clicking from an email client redirects appropriately afterwards
- **Resend confirmation** action on each pending row regenerates the token and emails it again. Rate-limited per user

### Security

- **Closes the OAuth-linking email-ownership gap.** Previously, `OmniauthCallbacksController#create` set `verified_at: Time.current` on every signed-in linking attempt, regardless of whether the OAuth-returned email belonged to the user. The new flow refuses to activate the sign-in method until the user proves mailbox ownership of the OAuth email. Pending authentications cannot sign in
- **Cross-user collision blocked.** A signed-in user re-OAuthing with credentials matching another user's existing authentication never transfers ownership; flash leaks no information about whether the token belongs to a different account
- **Cross-user verification spam prevented.** A signed-in attacker can no longer trigger fresh verification emails to a victim by re-OAuthing on the victim's pending UID — the cross-user check fires before the pending-resend branch
- **Per-user rate limit scoping** on `resend_verification`, `account/avatars#update`, and `workspaces/invitations#resend` (`by: -> { Current.user&.id || request.remote_ip }`). Prevents shared-NAT lockout where one user could exhaust another's rate bucket
- **Cross-user verify guard** on `Account::ConnectedAccountsController#verify` — a signed-in user clicking another user's verification link gets the same `invalid_or_expired` flash as a stale token, with no programmatic confirmation that the token belonged to a different account
- **Last-verified-method protection** now counts only verified authentications. Pending auths can always be cancelled (they grant no sign-in capability); a verified auth can only be removed if at least one other verified auth remains
- **Transactional destroy with row lock** (`SELECT ... FOR UPDATE` on Postgres/MySQL; `BEGIN IMMEDIATE` on SQLite) serializes concurrent DELETE requests, preventing the race where two simultaneous unlinks could both pass the count gate
- **Atomic pending-row creation** — the verification token is set in the same SQL write as the auth row's initial `save!`, eliminating the transient state (`verified_at: nil` AND `verification_token: nil`) where a crash mid-flow could leave a row that bypassed verification on a subsequent OAuth attempt
- **Production fix:** `omniauth-google-oauth2` returns `provider: "google_oauth2"` from real callbacks, but the `Authentication` enum stores `"google"`. The new `PROVIDER_MAP` normalizes the strategy name to the enum value at the controller boundary. Without this normalization, every real Google OAuth callback would have raised `ArgumentError: 'google_oauth2' is not a valid provider`. The bug existed pre-feature; this branch fixes it and adds a regression spec that exercises the strategy default

### Accessibility (WCAG 2.2 Level AAA target)

- **`role="status" aria-live="polite" aria-atomic="true"`** on the post-OAuth confirming banner so screen readers announce the verification-pending state
- **`<ul role="list">` + `<li>`** semantic markup for the authentication rows (was `<div>`/`<div>`)
- **`aria-label`** on each `<li>` describing pending-vs-verified state (e.g., "Google sign-in method, pending verification") so the row's status is programmatically determinable
- **Mailer body contrast fixed:** `.what` text bumped from `#6b7280` (4.8:1) to `#374151` (~10.6:1, AAA); `.footer` text bumped from `#9ca3af` (2.8:1, fails AA) to `#4b5563` (~7.6:1, AAA)
- All Resend / Cancel link / Unlink buttons retain `min-h-[44px] min-w-[44px]` touch targets and `focus:ring-2` focus indicators
- HTML mailer template links to a single descriptive CTA ("Yes, this was me — finish linking"), not "click here"
- Plain-text alternative provided for the verification email

### Infrastructure

- **1116 examples, 0 failures**; line coverage ~94%, branch coverage ~82%
- **35 commits** across two merged branches (`feat/verified-oauth-linking` and `chore/oauth-linking-followups`), each commit independently bisect-safe
- New schema column: `authentications.email` (nullable string, captures OAuth-returned email per row)
- New routes: `POST /account/connected_accounts/:id/resend_verification`, `GET /account/connected_accounts/verify/:token`
- New mailer: `AuthenticationMailer#link_verification_email` + HTML/text templates
- New model methods: `Authentication#display_provider`, `Authentication.display_name_for`, `Authentication#assign_verification_token` (non-persisting helper used by both the controller's atomic-create path and the model's `generate_verification_token!`), `Authentication#pending?`, `Authentication#token_expired?`, scope `Authentication.pending`. The legacy `Authentication#verification_token_expired?` now delegates to `token_expired?` so `TOKEN_LIFETIME` is the single source of truth for the 24h window
- New controller actions: `Account::ConnectedAccountsController#verify`, `#resend_verification`. `#destroy` rewritten to count only verified auths, with transactional row-lock semantics. `OmniauthCallbacksController#create` decomposed into `handle_existing_auth` / `handle_signed_in_link` / `handle_new_user_oauth` private branches with a `PROVIDER_MAP` normalization helper
- New locale files / blocks: `config/locales/en/oauth.en.yml` (new file with `omniauth_callbacks.create.*` keys), expanded `account.en.yml` blocks for `connected_accounts.index/destroy/verify/resend_verification`, `authentication_mailer.link_verification_email.*` keys
- Design doc and implementation plan preserved in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) at `superpowers/specs/2026-04-25-verified-oauth-account-linking-design.md` and `superpowers/plans/2026-04-25-verified-oauth-account-linking.md`

### Acknowledged limitations (deferred)

- **`info.email_verified: false` from Google is not gated.** If a Google IdP reports the OAuth email as unverified at the provider level, the new-user OAuth signup path still trusts it. Closing this requires a product decision (refuse OAuth signup, or require an additional verification step) and is tracked separately
- **Email comparison is byte-exact ASCII.** International/IDN addresses (e.g. `Юлия@example.ru`), Turkish dotless-i, and `+`-aliased addresses are treated as different from their canonical form, routing through verification even when visually identical to the user's primary. Acceptable for an English-first starter kit; tracked for later if/when IDN parity matters
- **Resend collision under simultaneous double-click** raises `RecordNotUnique` (DB unique index on `verification_token` saves correctness) but isn't gracefully rescued in the controller. Effectively rate-limited to 3-per-3min, so unlikely to manifest in practice

---

## v1.2.0 — Footer Cohesion + Developer Ergonomics

### Footer (user-facing)

- Two-row layout: brand + clustered navigation on row 1, centered copyright on row 2
- Nav links grouped into **Product** (About, Docs) and **Legal & privacy** (Privacy, Contact, Cookie settings) clusters separated by a vertical divider
- "Cookie settings" replaces the Biscuit gem's floating bottom-left button; the Biscuit preferences panel now reopens from an in-footer link via a 10-line `footer_controller.js` Stimulus controller that dispatches to the gem's hidden action button
- Responsive: mobile stacks vertically, tablet wraps and centers, desktop anchors left with the dev trigger pushed right
- WCAG 2.2 Level AAA target size: all footer links and the Cookie settings button use `min-h-[44px]`

### Developer tools (development-only, never rendered in production)

- **Clickable letter_opener link on "Check your email"** — the H2 on `sessions/check_email.html.erb` becomes a link to `/letter_opener` in development, opening the sent email in a new tab without leaving the auth flow
- **Accessibility-simulation drop-up in the footer** — toggle between Normal, Blur, Grayscale, Deuteranopia, Low contrast, and Cataract filters to pressure-test pages against vision-impairment conditions. Keyboard: Cmd/Ctrl+Shift+A opens, 0–5 jump to modes, Esc / Tab closes. State persists across reloads via localStorage; live region announces mode changes for screen readers
- **`aria-live` status region** on the a11y sim for WCAG 4.1.3 compliance
- **`aria-hidden` SVG filter defs** inlined in the partial; body-level CSS filter classes applied to `<body>` so modals and toasts receive the filter

### Fixes

- Disable CSP on `LetterOpenerWeb::ApplicationController` in development. The production CSP's `frame_src: :none` and nonce-enforced `script_src` blocked the gem's email-preview iframe and inline scripts. The engine is dev-only (mounted conditionally in `config/routes.rb`), so the override is scoped safely via `Rails.application.config.to_prepare`

### Infrastructure

- 1025 examples, 0 failures; coverage 94.46% line / 82.05% branch
- New view spec (`spec/views/shared/footer_spec.rb`) and system spec (`spec/system/footer_cookies_spec.rb`) covering footer structure, link clusters, and Cookie settings reopen flow
- Design doc and implementation plan preserved in [modelrails_base_docs](https://github.com/dschmura/modelrails_base_docs) at `superpowers/specs/2026-04-22-footer-cohesion-design.md` and `superpowers/plans/2026-04-22-footer-cohesion.md`

---

## v1.1.0 — Auth Redesign: Smart Sign-In + Magic Links

### Smart Sign-In Flow
- Unified email-first sign-in: single email field intelligently routes users
- Existing user with password → password form (within Turbo Frame)
- Existing passwordless user → magic link sent, inline "check your email" confirmation
- Unknown email → registration magic link sent, same inline confirmation
- "Send me a sign-in link instead" option on password form for password users

### Magic Links
- MagicLinkToken model with secure token generation, 15-minute expiry, one-time consumption
- Magic link sign-in for existing users (clears token after use)
- Passwordless registration via magic link (name-only form, no password required)
- Registration auto-creates verified email authentication record
- MagicLinkMailer with sign-in and registration email templates

### UI
- Turbo Frame inline transitions: check-email confirmation replaces sign-in form in-place
- Screen reader announcements via `role="status"` and `aria-live="polite"`
- `aria-hidden="true"` on decorative icons

### Security
- Rate limiting on magic link requests (5 per 3 minutes)
- Rate limiting on session lookup (10 per 3 minutes)
- No information leakage: same response for existing and non-existent emails
- Token consumed on first use, preventing replay

### Infrastructure
- 550 examples, 0 failures, 95.7% line coverage
- System specs for full magic link sign-in and registration flows
- Request specs for all magic link endpoints

---

## v1.0.0 — Phase 5B: Admin + Security + Polish

### Admin
- Rake tasks: `users:unlock[email]`, `users:verify[email]`, `users:suspend[email]`
- Suspend destroys all sessions and deactivates all memberships

### Real-Time
- Turbo Stream broadcasts on workspace and project streams
- Morph-based refresh (`broadcast_refresh_to`) — no partial rendering in models
- Workspace stream: membership, invitation, project, and settings changes
- Project stream: resource and project membership changes
- Resilient: broadcast failures never break primary operations

### Security
- Security headers initializer (X-Frame-Options, Referrer-Policy, Permissions-Policy, CSP)
- Rate limiting on registration and password reset endpoints (Rails 8 `rate_limit` DSL)
- All auth endpoints now rate-limited (login was already covered)

### Documentation
- Markdowndocs gem integration at `/docs`
- Starter docs: Getting Started, Architecture, Extending, Security
- Security docs include Top Secret and Rack::Attack production recommendations

### Infrastructure
- 439+ examples, 0 failures
- Brakeman clean (1 known mass assignment note)
- 95%+ line coverage

---

## v0.5.0-alpha — Phase 5A: Resource Layer + Activity Tracking

### Resources
- Polymorphic Resource registry with title, status (draft/published), position, and type allowlist
- Document content type with Action Text (Trix) rich text editor
- One controller serves all resource types — type-specific form/display partials
- ResourcePolicy enforces project membership access (viewer reads, editor creates, creator manages)
- Drag-and-drop reposition via Turbo Stream

### Activity Tracking
- ActivityLog model with polymorphic trackable, workspace scoping, and visibility enum (workspace/admin)
- Trackable concern with `after_commit` callbacks — opt-in per model
- Automatic creation/update tracking on Workspace, Membership, Invitation, Project, and Resource
- Sensitive attribute filtering (tokens, passwords stripped from metadata)
- Failure resilience — tracking errors never break primary operations
- Activity feed on workspace and project show pages

### Infrastructure
- Action Text installed for rich text content
- 404 examples, 0 failures, 95.8% line coverage
- 1 Brakeman note (same known mass assignment on project membership)

---

## v0.4.0 — Phase 4: Projects + Collaboration Spaces

### Projects
- Lightweight, Basecamp-style collaboration spaces within workspaces
- Project CRUD with slug routing, description, and max_projects enforcement
- Enum roles on ProjectMembership (creator/editor/viewer)
- Creator auto-assigned on project creation
- Direct member add for workspace members with role selection
- Pin/unpin projects for quick access (IDOR-safe: finds by current user)
- Logo upload with initials fallback, OKLCH primary color picker
- Soft delete (Discardable) for project archiving

### Personal Workspace
- Auto-created on user sign-up (invisible in consumer UIs)
- Backfill rake task for existing users: `rails users:backfill_personal_workspaces`

### Project Invitations
- Polymorphic invitation reuse (invitable_type: "Project")
- Auto-adds invitee to workspace (as viewer) + project in one step
- project_role field on invitations (editor/viewer only — "creator" injection blocked by validation)
- Branching accept! flow for workspace vs project invitations
- Handles archived project rejection, discarded member reactivation

### Renames
- `max_teams` → `max_projects` (column + all references)
- `manage_teams` → `manage_projects` (permission JSON data migration)

### Infrastructure
- Workspace membership cascade: deactivating a workspace member destroys their project memberships (in transaction)
- Pundit policies for Project and ProjectMembership
- 280 examples, 0 failures, 94.2% line coverage
- 1 Brakeman note: `user_id` in project membership strong params — intentional, guarded by Pundit creator-only policy

---

## v0.3.0 — Phase 3: Invitations + Membership Lifecycle

### Invitations
- Email invitations with role assignment and 7-day expiry
- Batch invitations (multi-line email input, single role)
- Magic link invitations (shareable token URL, no email required)
- Resend (regenerates token, resets expiry) and revoke actions
- Polymorphic invitable (ready for Team invitations in Phase 4)
- InvitationMailer with accept/decline links

### Accept/Decline Flow
- Token-based accept page (works for authenticated and unauthenticated users)
- Unauthenticated users redirected to registration, auto-joined after sign-up
- Token-based decline with confirmation page
- Guards against expired, revoked, and already-used invitations

### Membership Lifecycle
- Role change by Owner/Admin
- Member deactivation (soft delete) with last-owner protection
- Member reactivation
- Ownership transfer (atomic: promote target, demote self)

### Authorization (Pundit)
- Pundit policies for Invitation, Membership, Workspace, Settings, Branding
- Permission checks via Role.permissions JSON (manage_workspace, manage_members, manage_teams, manage_settings)
- Retrofitted Phase 2 controllers (replaced inline role checks)
- Graceful rescue_from for unauthorized access

### Infrastructure
- 217 examples, 0 failures, 92.3% line coverage
- 0 Brakeman warnings

---

## v0.2.0 — Phase 2: Workspaces + Multi-tenancy + Ownership + Branding

### Workspaces
- Create, edit, and archive workspaces with auto-generated slugs
- Path-based routing (`/workspaces/:slug/...`)
- Plan enum (free, pro, enterprise) with no tier enforcement (forker's job)
- Configurable max members and max teams per workspace

### Multi-tenancy
- `Current.workspace` for request-scoped workspace context
- `Tenanted` concern with explicit `for_current_workspace` scope (no default_scope)
- `WorkspaceScoped` controller concern for nested controllers
- Session-tracked current workspace for navigation state

### Roles and Membership
- 4 seeded system roles: Owner, Admin, Member, Viewer
- Permissions JSON on roles (data model ready for Phase 3 Pundit policies)
- Workspace-scoped custom roles at data model level
- Creator auto-assigned as Owner on workspace creation
- Read-only members list
- Owner/Admin role check on settings and branding

### Branding
- Workspace logo upload (Active Storage) with initials fallback
- OKLCH primary color picker with live CSS variable preview (Stimulus)

### UI
- Workspace switcher dropdown in navigation (keyboard-navigable)
- App theme updated from cyan to sky throughout
- `Discardable` concern for consistent soft delete pattern

### Infrastructure
- Bullet gem for N+1 detection (raises in test, alerts in development)
- Brakeman verified clean (0 warnings)
- 133 examples, 0 failures, 89.7% line coverage

---

## v0.1.0 — Phase 1: Auth + Users + Static Pages

### Authentication
- Email/password sign-up with 12-character minimum and Pwned breach detection
- Sign in/out with Rails 8 DB-backed sessions
- Account locking after 5 failed login attempts, auto-unlock after 1 hour
- Password reset using Rails 8.1 built-in signed tokens
- Email verification with token-based flow and 24-hour expiry
- Resend email verification

### OAuth
- Google and GitHub sign-in via OmniAuth
- Automatic account linking by matching email
- Signed-in users can link additional OAuth providers
- OAuth-only users can add email/password sign-in

### Account Management
- Profile editing (first name, last name, email)
- Avatar upload via Active Storage with Gravatar fallback
- Connected accounts view with unlink protection for last sign-in method
- Theme preferences (light, dark, system) with Turbo Stream and Stimulus

### Static Pages
- Home, About, Privacy, Contact with I18n and WCAG 2.2 AAA accessibility

### Infrastructure
- Rails 8.1 with SQLite, Propshaft, Importmaps, TailwindCSS 4
- RSpec, FactoryBot, Capybara + Playwright test suite (77 examples)
- SimpleCov coverage reporting
- Devcontainer configuration for VS Code / Codespaces
