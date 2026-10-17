---
title: Deployment
description: Deploy ModelRails to production with Kamal — SQLite topology, Solid Queue graduation path, SSL configuration, and the runtime invariants that keep deploys safe.
keywords: kamal deploy production sqlite solid queue single-host stop_timeout graduation rolling deploy ssl https proxy registry github container preflight rails_host placeholder
---

# Deployment

This template ships with **Kamal** for zero-downtime container deploys to your own server(s). Most of the configuration follows standard Kamal + Rails 8 conventions; this page covers the non-obvious parts that exist *because* this template defaults to SQLite + Solid Queue in-process.

> **Design rationale:** the topology decisions on this page came out of an Ops panel review (Rosa Gutiérrez, Donal McBreen, Aaron Patterson, Nick Janetakis).

## The SQLite-on-Rails constraint

This template defaults to **SQLite** (with Solid Queue, Solid Cache, and Solid Cable in-process). SQLite is single-writer and single-host by design — it cannot be shared across machines.

That shapes everything in `config/deploy.yml`:

- `servers.web` runs on **exactly one host** — a second host would be a second SQLite file, not a replica
- The commented `servers.job:` block is a **trap** for SQLite users — uncommenting it requires migrating to a network-attached database first
- Kamal's normal rollover (boot the new container, wait for it to pass its health check, stop the old one) briefly runs two containers against the same volume. On one host that is the situation Puma's own workers are already in — SQLite serializes same-host access with file locks — so the template does nothing to fight the rollover

The template ships these defaults safely; you only need to think about them when you outgrow SQLite. See [Graduation checklist](#graduation-checklist) below.

## First deploy

### 1. Configure `config/deploy.yml`

Replace placeholders with your real values:

```yaml
servers:
  web:
    hosts:
      - <YOUR-SERVER-IP>   # was: 192.168.0.1 — exactly one; see above

registry:
  server: ghcr.io          # or your registry
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

### 2. Set secrets

**`.kamal/secrets` is tracked in git. Never put a credential in it — put a reference.**

Kamal reads that file (and its `-common` / `.<destination>` siblings) with dotenv
plus inline command substitution, so every value resolves at deploy time. Two
forms work, and both are OS-neutral:

```bash
# From the environment of whoever runs `kamal deploy` — CI provides these
# from its own secret store.
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Or fetched from a password manager at deploy time.
KAMAL_REGISTRY_PASSWORD=$(op read op://YourVault/ghcr/token)
```

The shipped file already uses the reference form for `RAILS_MASTER_KEY`; follow
it. `spec/code_smells/kamal_secrets_hold_no_literals_spec.rb` fails the suite if
a literal appears, naming the key but never printing the value.

Where the raw value should live, in preference order:

1. **A password manager**, read inline with `$(...)`. Nothing lands on disk.
2. **Your CI platform's secret store** (GitHub Actions secrets), exported into
   the deploy job's environment.
3. **An exported shell variable**, if you must — but keep it out of your shell
   profile. Anything exported there is inherited by *every* process you launch
   and shows up in process-environment dumps.

For `RAILS_MASTER_KEY`: the template uses per-environment credentials
(`bin/rails credentials:edit --environment production`, see [Forking](forking)),
so the key is `config/credentials/production.key` — not the single
`config/master.key` a default `rails new` would use. The tracked
`.kamal/secrets` already reads that file; the value itself is what goes into a
managed platform's settings.

> A root `.env` does **not** reach Kamal. Kamal's dotenv parses its own secrets
> files, not `.env` — that file is for local Rails only.

### 3. Configure outbound mail

Sign-in is an email. Magic links, invitations and password resets all leave
the box through Action Mailer, so a deployment with no mail server boots,
reports healthy at `/up`, and nobody can sign in. The preflight guard refuses
that boot, which is why this step sits before the first deploy.

Mail leaves over SMTP, configured entirely from the environment. Every
provider named below speaks SMTP, so moving between them is a change of
values, never of code:

| Variable | Meaning | Default |
| --- | --- | --- |
| `SMTP_ADDRESS` | The provider's SMTP host | none; the guard refuses `localhost` and placeholders |
| `SMTP_PORT` | Submission port | `587` |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | The provider's credentials, as secrets | none; the guard refuses a blank one |
| `SMTP_DOMAIN` | The HELO domain | `RAILS_HOST` |
| `MAIL_FROM` | The sender on every message | `noreply@RAILS_HOST` |

`config/deploy.yml` already carries the Postmark host under `env.clear` and the
two credentials under `env.secret`; `.kamal/secrets` references them from the
deployer's environment. A send that could not reach the server (a connect
timeout, a refused connection, a busy reply) is retried four more times over
about seven minutes, inside a magic link's fifteen. Any other failure raises at
once, so it fails its Solid Queue job where you can see it rather than
vanishing; a read timeout is not retried, because the server may already have
accepted the message.

#### Postmark, the worked default

Transactional only, and free to validate on: the developer tier sends a
small number of messages a month at no cost, and the first paid tier covers
thousands. Check the current limits on their pricing page.

1. Create a server for this app and keep its **Server API token**.
2. Add your domain under Sender Signatures and publish the two DNS records it
   gives you (DKIM and Return-Path). Wait for both to verify.
3. Export the token twice, as both halves of the credential, and deploy:

   ```bash
   export SMTP_USERNAME=<server-api-token>
   export SMTP_PASSWORD=<server-api-token>
   kamal deploy
   ```

`SMTP_ADDRESS` is already `smtp.postmarkapp.com` and the port `587`. Messages go
to the server's default transactional stream.

#### Amazon SES over SMTP, the second recipe

The path when a fork needs an EU region, a BAA, or volume pricing. Same six
variables; the differences are where the values come from.

1. In the region you want, verify the sending domain (Easy DKIM publishes the
   DNS records for you).
2. Create **SMTP credentials** from the SES console. They are an IAM user's
   derived SMTP password, not the account's access keys.
3. Request production access; a new account starts in a sandbox that only
   delivers to verified addresses.
4. Point the deployment at the regional endpoint:

   ```yaml
   # config/deploy.yml, under env.clear
   SMTP_ADDRESS: email-smtp.eu-central-1.amazonaws.com
   SMTP_PORT: 587
   ```

#### Domain authentication, whichever provider

Send from a subdomain you reserve for the app's mail (`mail.yourdomain.com`),
so its reputation is its own. Publish SPF and DKIM as the provider instructs,
then a DMARC record, starting at `p=none` with a reporting address and
tightening once the reports show only your mail. Keep marketing mail, if the
app ever sends any, on a separate stream or provider: one bounce storm from a
campaign should never cost a sign-in link its reputation.

#### Assumptions, and what reopens them

- **No protected health information travels by email** (decided 2026-10-01).
  A magic link or a "you have a new message" notice carries none; an
  appointment detail would. A fork that must send such content needs a
  provider that signs a Business Associate Agreement; SES under the AWS
  agreement is the documented path, and this step is where it gets rewritten.
- **EU residency** is per fork. Postmark processes in the United States under a
  data-processing agreement, which satisfies GDPR for most apps; a fork that
  promises EU residency uses the SES recipe in an EU region.
- **Inbound mail** (replies into the app, an address users can write to) is the
  trigger for an API transport. Postmark and SES both receive mail; neither is
  wired here.
- **Self-hosting the mail server** becomes worth a look when sending costs
  exceed the hours it takes to run one. Deliverability — IP reputation,
  warm-up, blocklists — is the cost that moves from the provider to you.

To check a deployment: request a magic link for your own address and read the
mail. If nothing arrives, `kamal app logs` shows the failed job with the
provider's response.

### 4. Bootstrap and deploy

```bash
bin/kamal setup     # First-time only — installs Docker on the host
bin/kamal deploy    # Subsequent deploys
```

CI verifies your production image builds on every pull request that touches a build input (the `image_scan` workflow's cold build) and on every push to `main` (the `docker_build` workflow; see [Getting Started](/docs/developer/getting-started)), and the pre-push hook runs the same build locally when you change one, so the first time you run `kamal deploy` you're not also debugging Dockerfile issues.

Once the app is up, mint the first instance operator — see [Instance operations: Day one](operations#day-one-on-an-invite-only-instance).

## Production-safety invariants

The template ships two Kamal settings that aren't obvious from the Rails scaffold:

### `stop_timeout: 45` at top level

Docker's SIGTERM→SIGKILL grace for a proxied role is 10 seconds. With `SOLID_QUEUE_IN_PUMA: true` (the template default), Solid Queue's `on_worker_shutdown` hook needs longer to drain in-flight jobs before SIGKILL. **45 seconds** is the floor; raise it if you run long-running jobs in-process.

An earlier revision spelled this `stop_wait_time` and paired it with a `max-replicas: 1` docker option — neither is a key Kamal 2 or Docker knows, and `kamal config` rejected the file before touching a host. `spec/code_smells/template_invariants_spec.rb` now runs `config/deploy.yml` through Kamal's own loader, which is the check that catches a misspelled key on the day it is written.

### Builder args pass Ruby version through to the production image

```yaml
builder:
  args:
    RUBY_VERSION: "4.0.7"   # Keep in sync with .tool-versions
```

This ensures `kamal build` always produces an image matching the Ruby version Bundler enforces in `Gemfile.lock`. If `.tool-versions`, `Dockerfile` `ARG RUBY_VERSION`, and `deploy.yml` `builder.args.RUBY_VERSION` ever drift apart, the integration spec at `spec/code_smells/template_invariants_spec.rb` will fail.

## Solid Queue topology

The template ships `SOLID_QUEUE_IN_PUMA: true` in `deploy.yml` env. This runs the Solid Queue **Supervisor inside the web server's Puma process** — one container handles both HTTP requests *and* background jobs.

**This is the right default for the one-box SQLite deploy.** Two containers, one VPS, one `kamal deploy`. No accessory networking. No job-server-can't-reach-SQLite-file issues.

**It is not the right default forever.** Recurring jobs share Puma's GVL with HTTP requests, and a deploy restart can SIGKILL jobs mid-execution if `stop_timeout` is too low.

### Graduation checklist

When you outgrow this default — typically when you add a second web server, or when sustained job volume exceeds ~10 jobs/sec — follow these four steps **in order**:

1. **Add a database accessory.** Uncomment the `accessories:` block at the bottom of `config/deploy.yml` (it ships with a MySQL template — adapt to Postgres or your preferred DB). Migrate your SQLite data to the new database.

2. **Set `DB_HOST` in `env.clear`.** Point Active Record at the accessory's internal Kamal network address.

3. **Flip `SOLID_QUEUE_IN_PUMA: false`.** This stops the in-Puma supervisor.

4. **Uncomment the `servers.job:` block** in `config/deploy.yml`. This declares a separate `bin/jobs` supervisor host. The image is the same — only the `cmd` differs.

You can now add web hosts too — `servers.web.hosts` is a list — once `web` is no longer pinned to single-host SQLite semantics.

## SSL configuration: paired changes required

TLS has two halves: the Rails settings in `config/environments/production.rb` and the `proxy:` block in `config/deploy.yml`. They are a package deal — running one without the other silently breaks sessions or takes the site down.

### The three Rails settings (already enabled — leave them)

The template ships all three **live** in `config/environments/production.rb`. There is nothing to uncomment on the Rails side:

```ruby
# Trust the SSL-terminating proxy's X-Forwarded-Proto header.
# Without this, Rails sees only the plain HTTP from kamal-proxy
# inside the container, so cookies won't get the Secure flag.
config.assume_ssl = true

# Redirect HTTP → HTTPS, enable Strict-Transport-Security header,
# mark cookies Secure. Requires assume_ssl so the redirect logic
# can detect requests that are already HTTPS via the proxy.
config.force_ssl = true

# Exclude the Kamal health check endpoint from the HTTPS redirect.
# kamal-proxy hits /up over HTTP inside the container — without
# this, health checks 301-redirect and fail, causing Kamal to
# mark the app unhealthy and refuse to roll forward.
config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
```

### The Kamal proxy setting (your job — this is the half that ships disabled)

The `proxy:` block in `config/deploy.yml` ships commented out because it needs your real domain. Enabling it is the actual SSL task on first deploy:

```yaml
proxy:
  ssl: true
  host: yourdomain.com
```

> **The trap: deploying with the proxy block still commented out looks healthy and is completely down.** Because `force_ssl` is already live, every browser request gets 301-redirected to an HTTPS port nothing is serving. But kamal-proxy health-checks `/up` over plain HTTP inside the container, and `ssl_options` deliberately excludes `/up` from the redirect — so the health check passes, Kamal reports the deploy green, and no human can reach the site. If your first deploy "succeeded" but the browser can't connect, this is why.

### Why they can't be enabled independently

Valid combinations:

- ✅ Proxy enabled + the three shipped Rails settings → correct production behavior
- ✅ TLS terminated at your own load balancer (multi-server setups) + the three shipped Rails settings → correct, provided the balancer forwards `X-Forwarded-Proto`

Broken combinations:

- ❌ Proxy commented out with the shipped Rails settings (the as-shipped state, deployed unchanged) → green health check, dead app (the trap above)
- ❌ `force_ssl` on, `assume_ssl` off, proxy on → redirect loop (app can't detect proxy's HTTPS signal, redirects every request)
- ❌ Rails settings disabled, proxy on → works, but no HSTS and cookies aren't `Secure` — don't ship that

### SSL deployment checklist

Before the first deploy:

- [ ] Uncomment the `proxy:` block in `config/deploy.yml` and set `host:` to your real domain
- [ ] Point your domain's DNS at the server first — kamal-proxy obtains the Let's Encrypt certificate on demand, which fails if the name doesn't resolve to the host yet
- [ ] Leave `assume_ssl` / `force_ssl` / `ssl_options` in `config/environments/production.rb` as shipped — they are already enabled; there is nothing to uncomment

## Production preflight

`config/initializers/required_production_config.rb` refuses to boot a production process when `RAILS_HOST` is unset or still a placeholder (`example.com`, anything ending in `.example`), when `SMTP_ADDRESS` is unset, `localhost` or a placeholder, or `SMTP_USERNAME` or `SMTP_PASSWORD` is blank (see [Configure outbound mail](#3-configure-outbound-mail)), or when the Active Record encryption keys are missing from the production credentials. The reason it refuses rather than warns: every mailer link — magic links, password resets, invitations — is generated from `RAILS_HOST`, and DNS-rebinding protection (`config.hosts`) is derived from it. With a placeholder value the app boots, `/up` reports healthy, and nobody can sign in. Missing encryption keys fail the same way — healthy `/up`, then the first read of a user raises. A failed boot is the only version of either failure you can see. Keys: `bin/rails db:encryption:init`, pasted into `bin/rails credentials:edit --environment production` ([Forking](/docs/developer/forking#bootstrap-secrets-and-configuration)).

Rules the guard follows:

- **Deterministic checks only** — unset, or a value that can never have been a working deployment (`example.com` is IANA-reserved per RFC 2606; `.example` is the TLD `bin/fork` substitutes into placeholders — neither can ever be a real host). A configuration that served traffic yesterday can never fail a restart today. Heuristic placeholder sweeps belong in `bin/fork` and CI, not in a boot-time guard.
- **Build-time boots are exempt.** The Dockerfile's `assets:precompile` runs with `SECRET_KEY_BASE_DUMMY=1` and legitimately has no deployment ENV; the guard skips those boots.
- **Set the value, never silence the check.** There is no bypass variable by design. To opt out permanently: `git rm config/initializers/required_production_config.rb` — the file is self-contained, so deleting it is one command and (since it is not on the `merge=ours` list) it stays deleted until upstream deliberately reintroduces it, which the changelog would note.

Set `RAILS_HOST` under `env.clear` in `config/deploy.yml` (Kamal) or as a plain environment variable elsewhere.

## Health check

Kamal hits `/up` on the container to determine if a new version is healthy enough to receive traffic. Rails 8 ships this endpoint by default (`Rails::HealthController#show`). The SSL exclusion above keeps it reachable over plain HTTP inside the container's network namespace.

If you customize the health check path, update both:

- `config/deploy.yml` — Kamal proxy's `healthcheck.path` (default `/up`)
- `config/environments/production.rb` — the `ssl_options` redirect exclusion lambda

## Storage volumes

`config/deploy.yml` declares one persistent volume:

```yaml
volumes:
  - "modelrails_base_storage:/rails/storage"
```

This holds:

- The primary SQLite database (`storage/production.sqlite3`)
- Solid Queue's database (`storage/production_queue.sqlite3`)
- Solid Cache (`storage/production_cache.sqlite3`)
- Solid Cable (`storage/production_cable.sqlite3`)
- Active Storage file uploads (if you use disk storage)

**Back this volume up off-server.** Losing it loses your entire app state. The recommended pattern is a periodic snapshot of `/var/lib/docker/volumes/modelrails_base_storage/_data` to S3-compatible storage. Migrating off SQLite to a networked DB only solves part of this — Active Storage attachments still live here unless you also configure S3 storage.

## File serving is already offloaded — don't configure X-Sendfile

The production image runs Thruster in front of Puma, and large-file offload is
**automatic**: Thruster announces sendfile support on every proxied request
(`X-Sendfile-Type: X-Sendfile`), and `Rack::Sendfile` — present in the default
middleware stack — honors that per-request announcement. `send_file` responses,
including Active Storage disk-service downloads, are served by Thruster's Go
process instead of tying up a Puma thread. There is nothing to enable.

**Never set `config.action_dispatch.x_sendfile_header` explicitly** (blog posts
sometimes suggest it). The explicit form applies *unconditionally*: on any
deploy where Thruster isn't in front — a managed platform's nginx, bare
`rails server` — Rack::Sendfile strips the response body and file downloads
return empty, a production-only failure CI can't catch. The announce-per-request
mechanism is deployment-agnostic; leave it alone.

## Common commands

```bash
bin/kamal deploy            # Standard deploy
bin/kamal app logs -f       # Tail container logs
bin/kamal app exec -i 'bin/rails console'   # Console on prod
bin/kamal app exec 'bin/rails db:migrate'   # Run a one-off task
bin/kamal redeploy          # Re-pull image and restart (no rebuild)
bin/kamal rollback          # Revert to the previous deploy
```

Aliases defined in `config/deploy.yml` (you can shortcut these):

```bash
bin/kamal console           # = app exec --interactive --reuse "bin/rails console"
bin/kamal shell             # = app exec --interactive --reuse "bash"
bin/kamal logs              # = app logs -f
bin/kamal dbc               # = bin/rails dbconsole with credentials
```

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| `bundle install` fails in Docker build with "Could not find version file .tool-versions" | `.tool-versions` not copied before `bundle install` runs | `Dockerfile` — the `COPY Gemfile Gemfile.lock .tool-versions ./` line; regression test in `spec/code_smells/template_invariants_spec.rb` |
| Deploy succeeds but app returns 502 | Health check failing because of HTTPS redirect | `config.ssl_options` excludes `/up` from `force_ssl` redirect |
| Jobs disappear mid-deploy | `stop_timeout` too short for Solid Queue drain | `config/deploy.yml` `stop_timeout: 45` or higher |
| `kamal deploy` from devcontainer fails with "docker: command not found" | `docker-outside-of-docker` feature not active | `.devcontainer/devcontainer.json` features; rebuild container |
| `kamal …` dies with `ConfigurationError: unknown key` before touching a host | A key Kamal 2 doesn't know in `config/deploy.yml` — Kamal validates the whole file first | `bin/kamal config`; the template-invariants spec runs the file through Kamal's loader |
| Two containers visible during deploy | Kamal's rollover: the new container boots and passes its health check before the old one stops | Expected on one host — SQLite serializes same-host access. A second *host* is the problem, never a second container |
| Deploy takes unusually long with no error, on a release carrying an `activity_logs` migration | SQLite has no `ALTER TABLE ADD CONSTRAINT`, so Rails implements constraint changes as a full table rebuild (`CREATE` / `INSERT … SELECT` / `DROP` / `RENAME`). On a large `activity_logs` that copy runs inside `db:prepare` at boot, before the new container reports healthy — and the old container is serving against the table being rebuilt the whole time | Check the row count before deploying (`bin/kamal app exec 'bin/rails runner "puts ActivityLog.count"'`). If it is large, run `ActivityLogRetentionSweepJob` first to shrink the table, or accept the longer window deliberately |
| Deploy fails "container not healthy" on a slow boot | Health-check window too tight for the app's boot time | Raise `proxy.healthcheck.timeout` / boot limit in `config/deploy.yml`; the old container keeps serving until the new one is healthy, so a slow boot lengthens the deploy, not the outage |

## Deploying without Kamal

Kamal is this template's default deployment path, not a requirement. Nothing in
app code reads Kamal-specific configuration, so the app runs anywhere that can
provide the contract below — Hatchbox and similar managed platforms included.
Ignore `config/deploy.yml`, `.kamal/`, and `bin/kamal`; leave them in place so
upstream template merges stay clean (see [Forking](forking)).

Run `bin/deploy-guide` to get pointed at the right guide for your target.

### The portable contract

Required on any platform:

| Requirement | Detail |
|---|---|
| `RAILS_MASTER_KEY` | Contents of `config/credentials/production.key` |
| Persistent `storage/` | Writable, survives deploys — holds the SQLite databases and Active Storage files |
| Health check | Rails' built-in `/up` endpoint |
| `SOLID_QUEUE_IN_PUMA=true` | **Without it no background jobs run** (so no emails). Kamal's deploy.yml sets it; a managed platform won't. Alternative: run `bin/jobs` as a separate worker process |
| `RAILS_HOST` | Your app's hostname — mailer links default to `example.com` otherwise |

Optional tuning, all with working defaults: `WEB_CONCURRENCY` (1),
`RAILS_MAX_THREADS` (3), `JOB_CONCURRENCY` (1), `RAILS_LOG_LEVEL` (info).
Preset and seed variables (`SIGNUP_MODE`, `SIGNUP_PERMITTED_JOIN_STRATEGIES`,
`TENANCY_*`) are documented in [Presets](presets) and `.env.example`.

### The constraint that follows you everywhere

SQLite is single-writer, so run **exactly one web instance**. Scaling to a
second server on a managed platform is the same corruption risk as adding a
second host to `servers.web` under Kamal. Graduate to a networked database first (see the
[Solid Queue topology](#solid-queue-topology) graduation checklist above) —
that constraint belongs to the app, not to the deploy tool.

## See also

- [Getting Started](/docs/developer/getting-started) — Dev environment + CI pipeline overview
- [Background Jobs](/docs/developer/background-jobs) — Solid Queue topology, named queues, recurring jobs
- [Security](/docs/developer/security) — Auth, headers, rate limiting
- [Forking](/docs/developer/forking) — Identity rename, fork-owned files, pulling upstream updates
- `config/deploy.yml` — Inline comments document every option (Donal McBreen's "deploy.yml IS the documentation" principle)
