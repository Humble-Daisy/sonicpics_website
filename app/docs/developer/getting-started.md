---
title: Getting Started
description: Setup instructions and development workflow for ModelRails
keywords: setup install mise ruby bundle rspec tests oauth credentials development favicon icons branding ci lefthook git hooks accessibility
---

# Getting Started

## Prerequisites

- [mise](https://mise.jdx.dev/) for runtime version management (see `.tool-versions`)
- Chromium (managed automatically by Cuprite/Ferrum for system tests)

## The stack

Rails 8.1 or newer, and the pieces Rails ships: Propshaft for assets, import maps for JavaScript (with `tailwindcss-rails` for CSS), Hotwire (Turbo and Stimulus) for interaction, the built-in authentication generator's shape for sessions, and Solid Queue, Solid Cache, and Solid Cable on SQLite. That is a floor, not a preference list: there is no Devise, no JavaScript bundler, no React, no Sprockets, and no Redis-backed queue, and a fork that adds one of them is off the path every other page here describes. The `ModelRails/StackFloor` cop (`lib/rubocop`) fails a Gemfile line that brings in what the floor replaces, or pins `rails` below it, on commit.

### Rails comes from a pinned commit

The template runs on Rails main (8.2.0.alpha) for two features that have not shipped in a release yet: HTML templates compiled through Herb, and alternative text on Action Text attachments, which turns on Lexxy's ALT button. The Gemfile pins `rails` with `ref:` to one full commit, never a branch, so every checkout and every fork resolves exactly the code that was tested.

**Images saved before Lexxy 1.0.** Lexxy 0.9 wrote each uploaded image's file name into its alternative text, so on Rails main those images open the ALT dialog pre-filled with something like `IMG_2034.JPG`, which reads as a description someone wrote. A deployment that saved images under Lexxy 0.9 runs this once:

```bash
DRY_RUN=1 bin/rails action_text:clear_filename_alts   # counts the rich texts it would change
bin/rails action_text:clear_filename_alts
```

It removes `alt` only where it equals that same attachment's file name, leaves every other attribute and the surrounding text alone, and writes the body without touching the owning record or its timestamps. A second run finds nothing. Afterwards those images open the dialog empty and render like new uploads: an image nobody has described gets `alt=""`, so screen readers skip it and read the caption, which names the file once.

With `load_defaults 8.2`, HTML templates compile through [Herb](https://herb-tools.dev), which parses the HTML around the ERB. A template with broken structure, such as an unclosed tag or ERB output where an attribute name belongs, fails when it compiles, naming the file and line, instead of rendering malformed markup. `bin/rails herb:check` compiles every HTML template on the view paths without rendering anything. It reports one file today, a partial inside the biscuit-rails gem that the app overrides and never renders (#1341). `spec/code_smells/templates_compile_through_herb_spec.rb` runs the same check on every pull request, over the Lookbook previews, the Turbo Stream templates and the static pages in `public/` as well, with that partial as its one reviewed exception, which the spec drops once the gem's copy compiles. Other formats, such as text mailers and Turbo Stream templates, still compile through Erubi.

One test gem needs accommodating on Rails main: `rspec-rails` is pinned to a commit of its own main branch, where its Rails-main fixes are merged but not yet released (#1338). Bullet needed a load shim until 8.3.0 learned Active Record 8.2 (#1337); it now loads like any other gem, and `spec/config/bullet_spec.rb` proves it still catches an N+1.

Dependabot does not bump git-pinned gems: its bundler block ignores exactly the gems `Gemfile.lock` takes from git, and a template invariant keeps the two lists equal in both directions. The pin moves by hand:

- **When.** On every Rails security release, and otherwise at most once a month.
- **How.** Take the commit from `gh api repos/rails/rails/commits/main --jq .sha`, put it in the `ref:`, run `bundle update rails`, then the full suite, `bin/rails herb:check`, `bin/bundler-audit`, and both the production image and devcontainer builds. A security advisory written as "fixed in 8.2.0" may flag `8.2.0.alpha` even on a commit that has the fix; record that in the audit's ignore file with the commit that carries the fix, and remove the entry at the next move.
- **The way back.** When 8.2.0 ships, `gem "rails", "~> 8.2.0"` replaces the git line. The security-floor invariant and the StackFloor cop already accept that requirement, and the Dependabot invariant fails until the Rails gems leave the ignore list.

## Setup

```bash
mise install        # Install Ruby from .tool-versions
bin/setup           # Install deps, prepare database, start server
```

Or step by step:

```bash
bundle install
rails db:prepare
rails db:seed       # Seeds default roles (and, under the :shared preset, the bootstrap owner's operatorship)
bin/dev             # Start development server
```

**Confirm it worked.** Once the server is up, open <http://localhost:3000> — you should see the public home page. That's a working install: nothing below (OAuth, a master key, `.env`) is required to get this far. `.env` is optional and only needed for production-style runs or Kamal — copy `.env.example` to `.env` if you reach for those (`bin/dev` does not need it).

### Ruby version as single source of truth

`.tool-versions` is the canonical pin for Ruby. It feeds three downstream consumers automatically:

| Consumer | Mechanism |
|---|---|
| **Local mise / asdf** | Reads `.tool-versions` directly when you `mise install` |
| **Bundler** | `Gemfile`'s `ruby file: ".tool-versions"` directive — Bundler refuses to install gems if the running Ruby doesn't match. `Gemfile.lock` captures it in the `RUBY VERSION` block. |
| **Production Docker image** | `Dockerfile`'s `ARG RUBY_VERSION` defaults to the same value; `config/deploy.yml` `builder.args.RUBY_VERSION` passes it to `kamal build` |

Bump Ruby in `.tool-versions`, run `bundle install`, and the lockfile + production builds all pick it up. If you ever break this invariant — e.g., editing `Dockerfile` `ARG` without `.tool-versions` — the integration spec at `spec/code_smells/template_invariants_spec.rb` fails with a specific actionable error.

### Dev Container (optional, VS Code)

This template ships a Dev Container configuration so you can develop in an isolated environment that matches production runtime closely. Open the project in VS Code and accept the "Reopen in Container" prompt, or run **Dev Containers: Rebuild Container** from the command palette.

The container is built on `ruby:4.0.9-slim` — the **same base image as the production `Dockerfile`** (Option C: shared base, separate files). That means libvips, glibc, SQLite, and OpenSSL versions all match prod. Bugs that depend on those library versions surface in dev rather than only in production.

Capabilities baked in:

- **`docker-outside-of-docker`** feature → `kamal deploy` works *from inside* the devcontainer (your machine's Docker daemon is exposed)
- **Named bundle cache volume** → gems survive container rebuilds; no 5-min reinstall on each rebuild
- **SSH agent forwarding** → `kamal deploy` SSHes to target hosts using your existing keys
- **Port forwarding** → `:3000` (Rails) labeled in VS Code's Ports panel; the dev mail inbox (Letter Opener Web) is at `/letter_opener` on that same URL

When the container first boots, `.devcontainer/setup.sh` invokes `bin/setup` (the canonical Rails setup script) plus installs system packages mirroring the production Dockerfile. It ends with explicit next-steps guidance — copy `.env.example`, run `bin/dev`, visit `localhost:3000`.

Native development (no devcontainer) continues to work the same way as before — `mise install`, `bin/setup`, `bin/dev`. The devcontainer is an addition, not a replacement.

## Choose your app preset

modelrails_base supports several distinct product shapes — solo prosumer, internal single-tenant, multi-tenant SaaS — all built on the same multi-tenant data layer underneath. Before you start customizing, read [App Presets](/docs/developer/presets) to identify which shape matches what you're building. The defaults you just installed are the **Solo-default** preset; additional presets ship as they're built.

If you are forking the template, `bin/fork --preset personal|shared|none` records the
choice and writes it to `.env` — see [Forking](/docs/developer/forking). Switching
later is a migration, not a config flip, so it is worth deciding up front.

## Running Tests

```bash
bin/parallel-rspec                       # Full suite across all cores (what CI and pre-push run)
bundle exec rspec spec/path/to_spec.rb   # Focused single-process run
bundle exec rspec --format documentation # Verbose output
```

`bin/parallel-rspec` splits the suite across your CPU cores (each worker gets
its own SQLite database and browser) and adds two integrity gates: the executed
example count must match a dry-run enumeration, and the merged coverage must
meet the 40% floor. Each run records per-file timings to
`tmp/parallel_runtime_rspec.log`, so the next run balances workers by measured
runtime instead of file size (it falls back to file size when the log is
absent). Coverage report is generated at `coverage/index.html`.

### Spec conventions: the let diet, and when guards are warranted

Two conventions keep the suite readable as it grows (adopted from the
2026-08-14 panel review, #440):

**The let diet.** `let` is for records that several examples *in the same
context* genuinely share — it is not a place to park setup. Symptoms of let
bloat: the same paired `let!`s copy-pasted across contexts, and files whose
let count grows every month (the worked example:
`spec/requests/workspaces/members_spec.rb` carried the same
target-user/target-membership pair as `let!`s in six separate contexts; a
named `add_member` builder replaced them, 48 lets → 37, and each example's
cast is now visible at its call site). Rules of thumb:

- One example uses it → build it inline in the example, with a local
  variable named for its role (`target = add_member`).
- Several examples in one context share it → a single `let` in that
  context, built through a named builder so the reader sees *what* it is.
- Several contexts repeat it → extract a builder method; the repetition was
  a missing name, not shared state.

There is deliberately **no lint or count ratchet** for this: a counter is
trivially gamed (inline a let into a `before` block; nothing improves) and
teaches metric-satisfaction instead of design judgment. The convention is
enforced in review, by example.

**When a guard spec IS warranted.** Everything in `spec/code_smells/` earns
its place by naming, in its header, the shipped bug class it catches —
tenancy leaks, unasserted flashes, worker-colliding constants, live-class
migrations. That is the line: a guard fences *behavior that already bit
someone*; a preference with no incident behind it stays a documented
convention like the one above. Before writing a new guard, fill in the
blank "this guard exists because ___ shipped" — if you can't, write docs
instead.

### One runner at a time

Each test database is a single SQLite file, and `config/database.yml` installs a
5-second busy handler. Two spec runs against the same file therefore **do not
fail fast — they poison each other slowly**: every contended statement waits out
the handler, so a 12-minute suite can take over an hour and shed failures across
unrelated spec files that have nothing wrong with them.

A guard in the spec boot path refuses to start into that, naming the process
holding the database. It covers plain runs, parallel workers, and anything an
editor or agent launches, so there is no separate command to remember.

Two things worth knowing when it fires:

- **`TEST_ENV_NUMBER` is `""` for worker 1**, so `bin/parallel-rspec` and a plain
  `bundle exec rspec` share `storage/test.sqlite3`. A parallel run and a focused
  run *do* collide.
- **Stop a run by process group, not by name.** `pkill -f "bundle exec rspec"`
  matches the shell wrapper and orphans the `rspec` child process, which keeps the
  WAL lock — after which every later run fails in its first `create(...)`. Use
  `kill -- -<pgid>`, then confirm with `lsof storage/test.sqlite3*`.

When a run fails with `SQLite3::BusyException` or `ActiveRecord::StatementTimeout`,
reach for `lsof storage/test.sqlite3*` before suspecting the code.

## Development Tools

These affordances only render in `Rails.env.development?` and are invisible in production.

### Preview sent emails (letter_opener)

The `letter_opener_web` engine is mounted at `/letter_opener` in development (`config/routes.rb`) and set as the mail delivery method. Every email sent in dev is captured and previewed in the browser instead of going out over SMTP.

Two ways to open the inbox:

- Visit `http://localhost:3000/letter_opener` directly
- On the `sessions/check_email.html.erb` page (reached after requesting a magic link), the "Check your email" heading is itself a clickable link to the inbox, opens in a new tab. Saves a URL round-trip while iterating on auth flows.

A dev-only CSP override at `config/initializers/letter_opener_web.rb` disables the app's content-security policy on the gem's controllers so its email preview iframe and inline scripts render. Safe because the engine is mounted only in development.

### Accessibility simulation drop-up

A dev-only widget in the footer cycles through visual-impairment filters applied to the whole page. Useful for spotting color-dependency issues, low-contrast problems, or layouts that fall apart without color.

**Modes:** Normal · Blur · Grayscale · Deuteranopia · Low contrast · Cataract

**Keyboard shortcuts** (active when the dropdown is open):

- `Cmd/Ctrl+Shift+A` — open or close the dropdown
- `0`–`5` — jump directly to a mode
- `Esc` or `Tab` — close the menu

State persists across reloads via `localStorage`. The filter is applied to `<body>` (so modals, toasts, and all Turbo-replaced content receive it). Deuteranopia uses an SVG color matrix (`<feColorMatrix>`); the others use CSS filters. A live region announces mode changes for screen-reader users.

**Source:** `app/views/shared/_a11y_sim.html.erb`, `app/javascript/controllers/a11y_sim_controller.js`.

### Cookie settings dispatch (how the footer button works)

Biscuit's gem normally renders a floating "Manage cookies" button in the bottom-left corner. The app hides that button via CSS and replaces it with an in-footer button that triggers the gem's reopen action through DOM click dispatch. See `app/javascript/controllers/footer_controller.js` and the Footer Structure section of `ui-patterns.md` for the full pattern.

## Key Commands

| Command | Purpose |
|---------|---------|
| `bin/dev` | Start development server |
| `bin/parallel-rspec` | Run full test suite in parallel (CI parity) |
| `bundle exec rspec` | Run focused specs single-process |
| `bundle exec brakeman` | Security scan |
| `rails 'users:unlock[email]'` | Unlock a locked account |
| `rails 'users:verify[email]'` | Manually verify an email |
| `rails 'users:suspend[email]'` | Suspend a user |

The quotes around a bracketed task are for zsh, the shell a Mac opens by default: unquoted square brackets are a glob pattern, and the command stops at "no matches found" before Rails sees it.

## CI and Git Hooks

The project uses a two-gate CI pipeline:

### Gate 1: Local (Lefthook pre-push)

Runs automatically when you `git push`. No setup needed beyond `bundle exec lefthook install` (runs once after clone). The checks run one at a time, in this order, and the first failure stops the push:

| Check | Tool |
|-------|------|
| Stylesheet | `tailwindcss:build`, first, so system specs never read a half-written stylesheet |
| Security scan | Brakeman |
| Gem CVEs | bundler-audit, after updating the advisory database to the latest, as CI's fresh clone does; it needs the network. It audits the Hot Cell image's lockfile (`hotcell/Gemfile.lock`) too |
| Code style | RuboCop |
| ERB templates | erb_lint |
| Markdown | `mdl` |
| Full test suite | `bin/parallel-rspec`, including the axe-core WCAG 2.2 AAA audit on every system spec |
| Hot Cell image | `docker build --pull hotcell`, only when the branch changes something under `hotcell/`; the build installs libheif's HEVC and AV1 decoders by name and fails unless libvips registers its HEIF loader |
| Production image | `docker build`, last, and only when the branch changes a build input (`Dockerfile`, `.dockerignore`, `Gemfile`, `Gemfile.lock`, `.tool-versions`, `bin/docker-entrypoint`); refuses the push if Docker isn't running |

Pre-commit hooks also auto-fix Ruby style issues on staged files.

Don't skip the hooks. When one fails, run that check on its own to see why — each one's command is in `lefthook.yml`, and the suite is `bin/parallel-rspec` — fix it, and push again. `LEFTHOOK=0` and `--no-verify` do turn the hooks off, but they only move the failure: CI runs the same checks on the pull request, and the image build runs again on every push to `main`.

### Gate 2: GitHub Actions (on push/PR)

Runs the same checks plus additional linting:

| Job | What it checks |
|-----|---------------|
| `static` | One job for every static check: Brakeman, bundler-audit (gem CVEs), the importmap audit (JS dependency CVEs), RuboCop with GitHub annotations, the comment-block gate over the PR's diff, `mdl` (markdown) and `erb_lint` (ERB). Each check runs even after an earlier one fails, so one push reports every failure. They were four jobs; one runner minute bills for what took four. |
| `test` | Full RSpec with Cuprite, axe accessibility, screenshot artifacts on failure |
| `docker_build` | Verifies the production `Dockerfile` builds (catches build-time regressions that structural specs cannot). Its own workflow, run on every push to `main`, unfiltered. A pull request that changes a build input (`Dockerfile`, `.dockerignore`, `Gemfile`, `Gemfile.lock`, `.tool-versions`, `bin/docker-entrypoint`) gets the same proof from `image_scan`, which builds the identical image from scratch, so `docker_build` runs on a pull request only when its own workflow changes. The pre-push hook runs the same build locally through `bin/docker-build-check` on the same inputs. Uses GHA layer caching — cold builds ~3-5 min, warm builds ~30-60s. See [Deployment](/docs/developer/deployment). |

### Gate 3: Scheduled lanes (not on push/PR)

Four checks answer questions a per-PR run cannot, because what they watch changes without anyone committing. Each also runs on demand from the Actions tab (`workflow_dispatch`).

| Workflow | When | What it checks |
|----------|------|---------------|
| `js_advisory` | Daily | The same importmap audit as the `static` job, against `main` — an advisory published between pushes is otherwise invisible until the next PR happens to touch the tree. `static` stays the required check; this is additive. |
| `image_scan` | Weekly, plus every PR that changes a build input | OS-package CVEs in the production image, which appear without any code change. It builds the image from scratch, so on those PRs it is also the proof that the image builds. |
| `hotcell_image_scan` | Weekly where the `HOTCELL_SCAN` repository variable is set, plus every PR that changes `hotcell/` | The same scan of the [Hot Cell](/docs/developer/hot-cell) image. A fork that keeps the cell off leaves the variable unset and pays for no weekly build. |
| `fork_vocabulary` | Weekly | The whole suite under `spec/fixtures/vocabulary.course.yml`, proving the promise that a fork renaming its nouns keeps this suite green. The per-PR gate catches literal-noun copy assertions in the shapes it knows; this catches the rest. |

**Scheduled workflows switch themselves off in an inactive public repository.** GitHub disables them after 60 days with no repository activity — see [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows) (`schedule`). The condition is repository *visibility*, so a private fork is not affected; a public fork that goes quiet loses these four lanes silently and re-enables them with any repository activity.

### Development Workflow

1. Create a feature branch: `git checkout -b my-feature`
2. Write tests, implement, verify locally: `bin/parallel-rspec`
3. Commit (pre-commit hook auto-fixes Ruby style)
4. Push (pre-push hook runs full CI locally)
5. Open PR on GitHub (Actions run second round of checks)

### Turning a house cop off in your fork

Base ships eight house cops under `lib/rubocop` (`ModelRails/*`), configured in the base-owned `.rubocop/house.yml` and on by default. They are rules about how base writes code — the same kind of thing as the omakase config it inherits — and your fork is free to disagree with any of them. Do it in the fork-owned `.rubocop/app.yml`, which upstream never touches (`merge=ours`), with the reason on the line above:

```yaml
# Our admin area keeps a few verb routes on purpose; see ADR-7.
ModelRails/RestfulActions:
  Enabled: false
```

That is a decision with a name, which is what a reviewer or an agent reads first. It is not the place for offenses in code you inherited or wrote before a cop landed: those belong in `.rubocop_todo.yml`, which grandfathers by path and shrinks as files are fixed, while `app.yml` changes the rule itself. Never edit `.rubocop/house.yml` or `.rubocop.yml` in a fork; both are base-owned and every upstream sync would conflict.

### Linting Commands

```bash
bundle exec rubocop                    # Check Ruby style
bundle exec rubocop --autocorrect-all  # Auto-fix Ruby style
bundle exec rake markdown:check        # Check markdown
bundle exec rake markdown:lint         # Auto-fix + check markdown
bundle exec rake erb:check             # Check ERB templates
```

## Favicon and PWA Icons

The app ships with a multi-format favicon setup in `public/`:

| File | Purpose |
|------|---------|
| `favicon.ico` | Legacy browsers (any size) |
| `icon.svg` | Modern browsers (scalable, crisp at all sizes) |
| `apple-touch-icon.png` | iOS home screen bookmark |
| `icon-192.png` | PWA icon (192x192) |
| `icon-512.png` | PWA icon and splash screen (512x512) |
| `manifest.webmanifest` | PWA manifest (app name, icons, theme) |

These are referenced in both `app/views/layouts/application.html.erb` and `app/views/layouts/markdowndocs/application.html.erb` via link tags in `<head>`.

To replace with your own branding, swap the files in `public/` keeping the same filenames and sizes. Update `name` and `short_name` in `manifest.webmanifest` to match your app name.

## OAuth Setup (optional)

Email/password and magic-link sign-in work without this — set up OAuth only if you want Google/GitHub sign-in. Add credentials for Google and GitHub OAuth (per-environment; the template ships no credential files, and the first run generates the blob and key):

```bash
bin/rails credentials:edit --environment development
```

```yaml
oauth:
  google:
    client_id: your_id
    client_secret: your_secret
  github:
    client_id: your_id
    client_secret: your_secret
```

## Next steps

1. **[Choose your app shape →](/docs/developer/presets)** — Solo, Single-tenant, or Open SaaS. This is the most important decision; it sets signup, onboarding, and workspace behavior.
2. **[Extend the framework →](/docs/developer/extending)** — add your own workspace-scoped models, authorization, and features.
