---
title: Forking
description: Start a downstream app from this template and keep merging upstream improvements
keywords: fork template upstream downstream merge sync rename clone brand seams update jumpstart
---

# Forking this template

ModelRails is an **upstream template**: you clone it to start a product, build in
fork-owned files, and periodically merge upstream improvements back in — the same
workflow commercial Rails templates like Jumpstart Pro use.

Three things make the merges cheap:

1. **Shared git history** — your app is a true clone, so `git merge upstream/main`
   is an ordinary merge.
2. **Fork-owned files** — everything you are expected to rewrite (marketing pages,
   brand strings, your routes, your docs) lives in files upstream never edits again.
3. **A merge driver** — fork-owned paths are marked `merge=ours` in
   `.gitattributes`, so when both you and upstream changed one, the sync keeps
   your version (details in [Fork-owned files](#fork-owned-files)).

**Is this model right for you?** If you just want a starting point and never
plan to pull template improvements, skip the machinery: clone, delete the
`upstream` remote, and own everything (the thoughtbot Suspenders model). This
guide earns its keep when you want upstream fixes and features flowing into
your app for years.

Two pieces of shared machinery already update the easy way — the design system
(`modelrails_ui`) and the docs engine (`markdowndocs`) are gems, so improvements
to them arrive via `bundle update`, no merge involved. The merge workflow covers
everything else: the application code around the gems.

## Start a new app

Create an **empty** private repository on GitHub first (no README, no license — it
must be truly empty). Then:

```bash
git clone git@github.com:dschmura/modelrails_base.git myapp
cd myapp
bin/fork
```

`bin/fork` runs **before** `bin/setup`. It asks for your project name and tenancy
preset, then does the remote surgery and the identity rename in one commit, and
records your answers in `.fork.yml`. It prints every git command as it runs, so
you can read what it did — and finish by hand if you ever need to.

```bash
bin/fork --name myapp --preset personal --origin git@github.com:YOU/myapp.git --yes
bin/fork --dry-run    # print the plan, change nothing
```

It refuses to run on a dirty working tree: the identity rename wants to be one
clean commit you can always find again. Re-running is safe — it detects what is
already done, and completes a rename that was interrupted partway.

When run interactively it finishes by offering to run `bin/setup` for you (the
dev server is not started — that stays your call). Under `--yes`, or when stdin
isn't a terminal, it never does: scripted and CI runs stay fast and predictable.

### From a GitHub fork, or a fork of a fork

The template is meant to be forked, and forks get forked: an organization keeps
its own synced copy under its own name, and products start from that copy. The
shortest path is the **Fork** button, then a clone, then `bin/fork` with no
remote flags at all:

```bash
git clone git@github.com:YOU/myapp.git
cd myapp
bin/fork --name myapp --preset personal --yes
```

Your clone's `origin` is already your product and there is no `upstream` yet.
Git has no record of what a fork was forked from, but GitHub does, so when
nothing else names the template and the `gh` CLI is installed, `bin/fork` asks
GitHub for `origin`'s parent and records that URL in `.fork.yml`. That is the
repository you pressed Fork on — the organization's copy if you forked the
copy, the template if you forked the template. `bin/setup` reads the URL and
adds it as the push-disabled `upstream` in every clone. The script says which
it did: *template … (origin's GitHub parent)*.

Without `gh`, or when GitHub reports no parent, name the template yourself with
`--template URL`; an explicit flag always wins over the lookup:

```bash
bin/fork --name myapp --preset personal --template git@github.com:ORG/modelrails_base_wads.git --yes
```

`--template` is also how a copy under another name works on the **clone path**
(`git clone <the copy> myapp`, then `bin/fork --origin <your empty repo>`).
There `origin` *is* the template, so its GitHub parent would be one hop too far
and the script deliberately does not ask; `bin/fork` knows the template by
name — a remote ending in `/modelrails_base` — and `--template` extends that to
the copy. With the flag, an existing `upstream` equal to that URL counts as
configured, and an `origin` equal to it gets the same remote surgery as the
template itself. The match is URL equality, with or without `.git`, never a
looser name pattern: a repository of your own that merely *starts* with
`modelrails_base` is never mistaken for the template.

### By hand (what bin/fork does)

Use this if you'd rather drive it yourself, or to finish up after an interrupted
run:

```bash
# The template becomes a read-only "upstream" remote
git remote set-url --push origin DISABLED     # before the rename, so no window exists
git remote rename origin upstream             # a stray `git push upstream` now fails loudly
git branch --unset-upstream                   # or `git pull` would still pull the TEMPLATE

# Your new repository becomes origin
git remote add origin git@github.com:YOU/myapp.git
git push -u origin main

# Activate the fork-owned merge driver (bin/setup also does this for you,
# but doing it now means your very first merge is already covered)
git config merge.ours.driver true
```

Then work through the identity-rename table below.

Two things you'll notice afterwards, both intentional:

- `git remote -v` shows upstream's push URL as `DISABLED`. That string is not a
  real URL — it makes any accidental `git push upstream` fail loudly instead of
  writing to the template.
- Your `main` tracks `origin/main` (your repo), so plain `git pull` stays inside
  your app. Upstream only enters when you explicitly run `git merge upstream/main`.

Finally, record the cut point in the template repo — it answers "which template
version is myapp based on?" forever:

```bash
# in your modelrails_base checkout
git tag forks/myapp-baseline main && git push origin forks/myapp-baseline
```

> **Why not GitHub's "Use this template" button, or a GitHub fork?** "Use this
> template" squashes the entire history into one unrelated commit — every later
> `git merge upstream/main` would need `--allow-unrelated-histories` and conflict
> on everything both sides touched. And GitHub will not fork a repository into
> the account that already owns it. Clone + re-pointed remotes gives you a
> private repo **and** mergeable history.

**Every teammate** who clones your new repository runs `bin/setup` — and only
that. They must not run `bin/fork`; the identity rename is already committed, and
`bin/fork` will tell them so and send them here.

```bash
git clone git@github.com:YOU/myapp.git
cd myapp
bin/setup
```

`bin/setup` reads `.fork.yml` and does the per-clone work: adds the upstream
remote (push disabled), activates the merge driver, and writes the fork's
recorded tenancy preset into their `.env`. Those three things are per-clone, not
per-fork, which is why they live in setup rather than in the one-time script.
The git hooks are not among them: `bundle exec lefthook install` is a separate
one-time step per clone (see [Getting started](getting-started#gate-1-local-lefthook-pre-push)),
and until it runs a push runs nothing.

> Teammates need **read access to the upstream template repository** for the
> remote to be useful. If your template is private, grant it before they try to
> merge upstream — the remote will be added either way, but fetching will fail.

To verify the driver on any clone: `git config merge.ours.driver` should print
`true`. If it prints nothing, fork-owned files will conflict like ordinary files
on your next sync.

## Rename the identity

Do this before your first commit, so the rename is one clean commit you can always
find again.

| What | Where | Notes |
| ---- | ----- | ----- |
| Ruby module name | `config/application.rb` (`module ModelrailsBase`) | `bin/rails app:update` won't do this for you |
| Kamal service name | `config/deploy.yml` (`service:`) | Tags Docker containers; collides if two apps share a host |
| Docker image name | `config/deploy.yml` (`image:`) | Must match your registry path |
| Storage volume names | `config/deploy.yml` (`volumes:`) | Renaming later orphans the old volume — do it before first deploy |
| Brand strings | `config/locales/en/brand.en.yml` | Product name, description, copyright — fork-owned, one file |
| Brand colors | `config/locales/en/brand.en.yml`'s visual twin: `app/assets/tailwind/tokens/_brand.css` | Optional — swap the primary palette family here; re-prove AAA in CI ([Theming](theming)) |
| Brand mark | `app/views/shared/_site_mark.html.erb` (one `<svg>`, nothing else) + the icon set in `public/` | Replace wholesale; keep `fill="currentColor"`, `aria-hidden="true"`, and a `viewBox` with no width/height ([Extending](extending#customizing-the-site-logo)) |
| Vocabulary | `config/vocabulary.local.yml` | Your names for workspace and project (singular + plural); every template string follows ([i18n](i18n#vocabulary)) |
| Marketing copy | `config/locales/en/pages.en.yml` + `app/views/pages/` | Fork-owned — rewrite wholesale |
| Operations pages | `app/helpers/operations/fork_nav_helper.rb` | Return your own operations pages as `[label, path]` pairs; the operations nav lists them after the template's, with the same current-page cue |
| Languages | `config/application.rb` (`config.i18n.available_locales`) | Register a locale here *before* adding its files, or `I18n.t(locale:)` raises in production — see [Internationalization](i18n) |
| PWA app name | `public/manifest.webmanifest` (`name` / `short_name`) | Shown on the home screen if users install the PWA |
| CI image tags | `.github/workflows/ci.yml` + `image_scan.yml` (`tags:`) | Local-only build tags; cosmetic but confusing if stale |
| Devcontainer bundle-cache volume | `.devcontainer/devcontainer.json` | Optional; the invariant spec only checks the `bundle-cache` suffix |
| Fork provenance | `.fork.yml` | Written by `bin/fork`: your name, tenancy preset, and the template commit you forked from. Committed so every clone inherits the decisions — `bin/setup` reads the preset. Two template invariants read it: the placeholder-support-address check runs only when it exists, and the check that `bin/fork`'s rename targets still exist upstream skips when it does. Everything else is derived from the repository |
| Session cookie key | optional `config/initializers/session_store.rb` | Only if multiple forks will share a cookie domain |

Then verify nothing was missed:

```bash
grep -ri modelrails . \
  --exclude-dir={.git,tmp,log,coverage,storage,vendor}
bundle exec rspec
```

Expected leftovers: references to the **modelrails_ui** design-system gem
(`Gemfile`, `.modelrails_ui/`, generated component comments) — that's the
library's name, not your app's. Lookbook preview sample copy under
`spec/components/previews/` also mentions ModelRails; rename it or leave it,
nothing asserts on it. The full test suite and CI's production-image build are
the rename's safety net.

## Bootstrap secrets and configuration

The template ships **zero** encrypted credential blobs — your fork generates its
own on first edit:

```bash
bin/rails credentials:edit --environment development
bin/rails credentials:edit --environment production
```

Add OAuth keys and `mailer.from` (structure in [Getting Started](/docs/developer/getting-started)).
Your fork **may** commit its own `.yml.enc` blobs — normal for a private app; the
`.key` files stay gitignored. `.kamal/secrets` reads
`config/credentials/production.key` at deploy time.

Personal data — email addresses, names, company names — is encrypted at rest
with Active Record Encryption, and **production refuses to boot without the
keys**. Generate them once and paste the block into the production credentials:

```bash
bin/rails db:encryption:init
bin/rails credentials:edit --environment production   # paste the active_record_encryption block
```

Development and test read literal keys from `config/environments/development.rb`
and `test.rb` — a fresh clone and CI run with no secrets, and that data is
disposable. Rails applies those settings *over* credentials, so keys added to
development credentials are ignored until the environment-file lines are
removed. The `deterministic_key` has no rotation path in Rails: back it up
wherever the credentials key is backed up, because losing it loses every
email lookup. Which columns, and why some are deterministic:
[Security](/docs/developer/security#personal-data-at-rest).

For production you'll also set `RAILS_HOST`, pick a tenancy preset
(`WORKSPACE_ON_SIGNUP`), and choose a signup mode — see `.env.example`,
[Presets](presets), and [Deployment](deployment).

## Fork-owned files

These paths are yours. Upstream froze them the day the seams shipped and will
never meaningfully change them again; the `merge=ours` driver keeps your version
on every sync.

| Path | What goes there |
| ---- | --------------- |
| `config/locales/en/brand.en.yml` | Product name, description, copyright |
| `config/locales/en/pages.en.yml` | Marketing copy for your pages |
| `app/views/pages/**`, `app/controllers/pages_controller.rb` | Your marketing/static pages |
| `config/routes/app.rb` | Your product's routes (loaded by `draw(:app)`) |
| `.rubocop/app.yml` | Your RuboCop overrides — turn a house cop off here, with the reason ([Getting started](getting-started#turning-a-house-cop-off-in-your-fork)) |
| `config/markdowndocs_categories.local.yml` | Registers your own docs pages on this `/docs` index |
| `app/assets/tailwind/tokens/_brand.css` | Brand-color overrides — swap the primary palette family ([Theming](theming)) |
| `app/views/shared/_site_mark.html.erb` | The brand mark — a file that is one `<svg>` ([Extending](extending#customizing-the-site-logo)) |
| `public/icon.svg`, `public/icon.png`, `public/icon-192.png`, `public/icon-512.png`, `public/apple-touch-icon.png`, `public/favicon.ico` | The favicon and PWA icon set — same artwork, same filenames and sizes ([Getting started](getting-started#favicon-and-pwa-icons)) |
| `config/vocabulary.local.yml` | Your product's nouns — any subset; `config/vocabulary.yml` fills the rest ([i18n](i18n#vocabulary)) |
| `app/helpers/operations/fork_nav_helper.rb` | Your own operations pages for the operations nav, as `[label, path]` pairs |
| `config/initializers/project_tools.rb` | Register your own project tools (`ProjectTools::Registry.register`) — see [Extending: Project Tools](/docs/developer/extending#project-tools-registry) |
| `README.md` | Your product's README |

**Clientside (external client area).** Clientside is available in every preset and is enabled per-project, not per-deployment — a fork enables it on a project-by-project basis via the project's Clientside settings toggle. No fork-owned file change is required to activate it; the toggle is in the project settings UI. See [Clientside](/docs/user/clientside) for details.

### Vocabulary — you own the words, upstream owns the sentences

The template's copy never says "workspace" or "project"; it says `%{workspace}`
and `%{project}`, and a boot-time hook fills those from `config/vocabulary.yml`.
To rename, put your words in `config/vocabulary.local.yml`:

```yaml
workspace: { singular: "course", plural: "courses" }
project:   { singular: "team",   plural: "teams" }
```

Restart. Every template string, including the ones upstream adds next month,
arrives in your words — that is the point of this file existing instead of
you editing `workspaces.en.yml`. Two template specs keep it true: no locale
value under `config/locales/en/` may spell out the bare noun (`brand` and
`pages` excepted — those are yours to word), and every interpolation token must
be supplied. That first rule covers the files you add, so write your own
strings with `%{project}` too and they follow the rename the same way.

What it does not do. It does not rename models, tables, routes, or URLs —
those stay `workspaces` and `projects`, and a product whose UI says Course and
whose URL says `/workspaces/3` is the accepted shape. It does not touch the
user docs under `app/docs/user/`, which are markdown, not I18n; rename those
by hand. And it never adds an article: template strings are worded so no "a"
or "an" precedes a noun, and your own strings should be too. It does not
escape: a fork's noun lands unescaped in `_html` keys, which is fine for a
boot-time file only the fork edits and never a place for user input.

Unlike `pages.en.yml`, this file holds nothing upstream will ever change, so
`merge=ours` here carries none of the silently-missed-fix risk described above.

### Fork seams — method overrides

Beyond file-level seams, a handful of private methods are designed to be overridden in `ApplicationController` (or a concern it includes). These are stable hooks upstream won't break.

#### `authenticated_home_path`

Every post-auth landing routes through this single private method: `SessionsController`, magic-link verification, OAuth callback, registrations, and `redirect_if_authenticated`. The default is `root_path`.

Override it to send signed-in users somewhere other than root:

```ruby
# app/controllers/application_controller.rb
private

def authenticated_home_path
  dashboard_path   # or workspaces_path, events_path, etc.
end
```

This is the primary seam for [Workspace-optional (`:none`)](/docs/developer/presets-none) apps, where post-sign-in landing should be a workspace-agnostic home (a user profile, an event listing, a personal dashboard) rather than a workspace context. But it's useful for any preset — even Solo-default forks often want to land users on `/dashboard` instead of `/`.

### Tuning knobs you own

These constants are yours to change and are **not** merge-frozen: an upstream change to them will conflict on sync, which is the point — you decide.

- `NotificationPreferences::ALLOWED_RETENTION_DAYS` — the retention choices offered (`app/lib/notification_preferences.rb`)
- `NotificationPreferences::DEFAULT_RETENTION_DAYS` — the fallback for a row whose `retention_days` key is absent; the column default in `db/schema.rb` is what a new user actually gets — change both, or the column default wins
- `NotificationPreferences::NEVER_CAP_DAYS` — what a pre-PR-5 "Never" choice reads as
- `ActivityLogRetentionSweepJob::SECURITY_RETENTION_FLOOR` — how long credential-event audit rows are kept, regardless of the general window
- `hotcell/config.rb` and the Hot Cell accessory's `cpus`/`memory` — the sandbox's limits, sized to your host ([Hot Cell](/docs/developer/hot-cell), Tune it)

### How the merge driver actually behaves

The `merge=ours` driver is a conflict *resolver*, not a wall. During a sync:

- **You customized the file, upstream changed it too** → the driver keeps
  **your** version, silently — no conflict shown. This is the common case: you
  rewrite all of these paths early, that's why they're on the list.
- **You never touched the file, upstream changed it** → upstream's version
  flows in normally. The driver only runs when *both* sides changed a file.

Two consequences worth understanding:

**You can silently miss upstream fixes.** If upstream patches a bug in a file
you've customized (say `pages_controller.rb`), your next sync keeps your version
and the fix never arrives — with no warning. The update recipe below includes a
one-command check for exactly this.

This has already happened once, so here is the worked example. Until 2026-08-04
the template shipped its maintainer's **real support address** in
`config/locales/en/pages.en.yml`; PR #549 (`7fe2fa87`) replaced it with a
placeholder. That file is fork-owned — the forking guide tells you to rewrite it
wholesale — so every fork created before that date keeps the old address on
every sync, silently, indefinitely. Two ways to catch this class of miss:

- **At sync time** — the fork-owned-paths check in the update recipe below
  (`git log --oneline main..upstream/main -- config/locales/en/pages.en.yml …`)
  lists upstream commits that will *not* flow in. It only works before you
  merge: afterward the commit is in your history even though its content never
  reached your file.
- **Any time after** — grep for the concrete leftover. For this instance:

  ```bash
  git grep -n "modelrails.dev" config/locales
  ```

  A hit means you are still shipping the template's address; replace it with
  your own. Forks created (or re-synced) after the fix also get a durable
  guard — a fork-gated template invariant fails the suite while any
  placeholder support address survives.

**The driver must be active.** `bin/setup` activates it on any clone that has an
`upstream` remote. Without it, these paths conflict like ordinary files — verify
with `git config merge.ours.driver` → `true`.

`db/seeds.rb` is shared ground rather than fork-owned: everything above the
"Fork seam" marker at the bottom is template-owned; add your domain seeds below
the marker.

### Adding your own docs page

Drop `app/docs/my-feature.md` (same frontmatter as this file), then create
`config/markdowndocs_categories.local.yml`:

```yaml
My Product:
  - my-feature
```

Categories named like template ones ("Guides", "Features") **append** to them;
new names become new index sections. The docs-coverage spec keeps guarding
orphaned pages across both maps automatically.

## Pull upstream updates

### 1. Look before you merge

```bash
git fetch upstream
git log --oneline main..upstream/main                   # what's coming
git log --diff-filter=R --stat main..upstream/main      # what moved — plan renames, don't discover them mid-merge
```

Read `CHANGELOG.md` on `upstream/main` first — breaking changes and migrations
are called out under [Unreleased]. If a change sounds structural (schema,
`deploy.yml`), read its PR before merging, not after.

Then check whether upstream touched files **you own** — those changes will NOT
arrive through the merge (the driver keeps yours):

```bash
git log --oneline main..upstream/main -- \
  app/views/pages app/controllers/pages_controller.rb \
  config/locales/en/pages.en.yml config/locales/en/brand.en.yml \
  config/routes/app.rb config/markdowndocs_categories.local.yml \
  config/initializers/project_tools.rb \
  app/assets/tailwind/tokens/_brand.css README.md
```

If a commit there looks like a fix you want, cherry-pick it after the merge:
`git cherry-pick <sha>`, then adapt it to your version of the file.

### 2. Merge on a branch

```bash
git checkout -b chore/upstream-sync-$(date +%F)
git merge upstream/main
```

### 3. If you hit conflicts

| Conflict in | Resolution |
| ----------- | ---------- |
| Fork-owned paths | Shouldn't happen — the driver keeps yours. If it does, the driver isn't active: `git merge --abort`, run `git config merge.ours.driver true`, merge again |
| Identity values (`config/deploy.yml` service/image/volumes, `config/application.rb` module) | Keep your names; take any structural changes around them |
| `Gemfile` | Keep **both** sides' gems, then regenerate the lockfile |
| `Gemfile.lock` | Never hand-merge: `git checkout --theirs Gemfile.lock`, then `bundle install`, commit the regenerated result |
| Behavior (app code, specs, config) | Take theirs — unless you deliberately diverged, in which case consider sending your version upstream instead |
| Two migrations, same timestamp | Keep both; rename yours to a later timestamp with `git mv`, then re-run `bin/rails db:migrate` |
| `db/schema.rb` | Never hand-merge: `git checkout --theirs db/schema.rb`, then `bin/rails db:schema:regenerate`, which rebuilds it from both sides' migrations |
| Upstream renamed/moved a file you'd edited | Re-apply your edit at the new location, delete the old file. If the same resolution recurs every sync, turn on `git config rerere.enabled true` so git replays it for you |

A conflict looks like this — your side on top, upstream's below:

```text
<<<<<<< HEAD
    primary_cta: "Start organizing your photos"
=======
    primary_cta: "Get started free"
>>>>>>> upstream/main
```

Decide which line the file should have (here it's your marketing copy — keep
yours), delete the other line and all three marker lines, then `git add` the
file. That's the whole skill; the doctrine table tells you which side to favor.

### 4. Prove the merge

```bash
bin/rails db:migrate    # upstream may ship migrations
bundle exec rspec       # full suite green before the PR
```

Open a pull request into your app's main branch like any other change.

### If something looks wrong after the merge

- **A fork-owned file changed unexpectedly** — the driver wasn't active during
  the merge. Restore your version from before the sync:
  `git restore --source=main <path>`, commit, then fix the driver config.
- **Bundler errors** — regenerate instead of debugging the lockfile:
  `git checkout --theirs Gemfile.lock && bundle install`.
- **Tests fail** — run the failing spec alone, then
  `git diff upstream/main -- <file>` on the code it covers to see whether your
  divergence or the upstream change broke it.

### Cadence

Merge after each meaningful upstream change — don't bank up months of drift.
Small frequent merges conflict less than one big annual one; if upstream is
busy, a fixed weekly sync keeps every merge boring.

## Contribute a fix back

Make template-worthy fixes in a checkout of `modelrails_base` itself (branch →
PR), not in your app — `upstream` is push-disabled by design. If the fix already
exists as a commit in your app:

```bash
cd ../modelrails_base
git checkout -b fix/thing main
git remote add myapp git@github.com:YOU/myapp.git   # or ../myapp for a local checkout
git fetch myapp
git cherry-pick <sha>
```

Three guardrails before you open the PR:

- **Only template-owned files.** If the commit also touches fork-owned paths
  (your README, pages, brand strings), it would pollute the template — split the
  commit, or port the change by hand instead of cherry-picking.
- **Regular commits only, never merge commits** — cherry-picking a merge commit
  needs `-m` and rarely does what you meant.
- **Strip anything product-specific** (names, copy, config values) so the change
  reads as a template improvement.

## Stay mergeable

- **Prefer new files to edited template files** — new files merge clean by
  definition. New models, controllers, components, initializers, docs pages: all
  conflict-free.
- **Brand strings only in `brand.en.yml`** — if you find one hardcoded anywhere
  else, that's an upstream bug; report or fix it upstream.
- **Product routes only in `config/routes/app.rb`** — leave `config/routes.rb`
  to the template.
- **Gemfile: add, don't pin.** Append your gems with loose constraints
  (`"~> 1.0"`); pinning exact versions or git branches conflicts with upstream's
  dependency bumps every sync.
- **Treat `UI::*` primitives as upstream-owned** — extend by composing new
  components rather than editing the primitives; the planned design-system
  update engine will regenerate them.
- **Layouts and shared partials are template-owned but not frozen.** Adding a
  nav link to the header partial is fine — insert lines, don't restructure, so a
  future conflict has one obvious resolution.
- **When you must edit any template file** (an initializer, `application.rb`),
  make the edit additive — append rather than rewrite.
- **`.github/` is template-owned and churns weekly** — 33+ action refs are
  SHA-pinned and bumped by grouped Dependabot PRs (gem bumps arrive the same
  way, one grouped PR a week), and the suite's pin
  invariant fails on ANY unpinned `uses:` (yours included). Add fork CI as
  new workflow files, SHA-pinned with the `# <tag>` trailer the invariant
  reads; never edit the template's workflows in place.
- **Dependabot never bumps `modelrails_ui`, by config.** For a gem pinned by
  git tag, Dependabot keeps the lockfile SHA as the current version, so its
  default cooldown can propose the newest tag *older* than the pin as an
  update — it did, three times. The bundler block ignores the gem; a bump is
  a hand PR that diffs each vendored component against the tag it came from
  before regenerating (see [Components](components)). The suite's invariant
  fails if the ignore is removed. Rails and `rspec-rails` come from git
  commits too, and are ignored and moved by hand the same way (see
  [Getting started](getting-started)).
- **Fetching a URL a user typed?** Read the outbound-request (SSRF) posture
  in [Security](security) first — the template deliberately ships no
  fetch-by-URL feature, and the first fork that adds one owns the pinning.
