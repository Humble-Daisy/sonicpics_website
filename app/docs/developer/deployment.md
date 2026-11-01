---
title: Deployment
description: Deploy ModelRails to production with Kamal — SQLite topology, Solid Queue graduation path, SSL configuration, and the runtime invariants that keep deploys safe.
keywords: kamal deploy production self-hosted fnox age secrets sqlite solid queue single-host stop_timeout graduation rolling deploy ssl https proxy registry github container preflight rails_host placeholder
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

These steps go from a fresh fork to a deployed app you can trust, in order,
and each one ends with a check. They assume one cloud server and one person
deploying from a laptop. Three sections after them add to the path:
[More than one person deploys](#more-than-one-person-deploys),
[Hardware you run yourself](#hardware-you-run-yourself), and
[Changing the registry](#changing-the-registry), for the one default you may
outgrow. On a machine you run yourself, do that section's items alongside
step 1, before the first deploy.

### 1. Prepare the server

Rent a Linux server (a current Ubuntu LTS image works) and note whether it is
`amd64` or `arm64`. Before the first deploy touches it:

- **SSH keys only.** Give the provider your public key when you create the
  server, then make sure password login is off: `PasswordAuthentication no` in
  `/etc/ssh/sshd_config` and anything under `/etc/ssh/sshd_config.d/`, then
  `systemctl reload ssh`. Kamal logs in as `root` unless `ssh.user` in
  `config/deploy.yml` names someone else. Root with key-only login is a sound
  default: another user would need the `docker` group, and that group controls
  the host as fully as root does. On a machine you installed yourself, copy
  your key to the user the installer made (`ssh-copy-id`), then to root:
  `sudo install -d -m 700 /root/.ssh && sudo cp ~/.ssh/authorized_keys /root/.ssh/`.
- **A firewall open on ports 22, 80 and 443 only.** Use your provider's cloud
  firewall. A firewall on the host itself, such as `ufw`, doesn't cover ports
  Docker publishes, because Docker writes its own rules ahead of it.
- **Security updates install themselves.** On Ubuntu that is
  `unattended-upgrades`; `systemctl status unattended-upgrades` shows whether
  it runs. SSH is open to everyone, so its fixes can't wait for you.
- **Docker from Docker's own repository.** Install Docker Engine from
  [Docker's apt repository](https://docs.docker.com/engine/install/ubuntu/)
  before the first deploy. Otherwise `bin/kamal setup` installs it by piping a
  script from get.docker.com into a shell, which this template avoids
  everywhere else.
- **The host key, checked once.** Your laptop and CI verify it on every
  deploy, so check it once against a source you trust: the fingerprint your
  provider shows in the server's console output, or, on a machine in front of
  you, what `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` prints at its
  own keyboard. Then fetch the key over the network and compare:

  ```bash
  ssh-keyscan -t ed25519 <server-ip> > server.known_hosts
  ssh-keygen -lf server.known_hosts
  ```

  Only when the fingerprints match, add `server.known_hosts` to your
  `~/.ssh/known_hosts`. Keep the file: CI needs it in
  [step 6](#6-deploy-from-ci). A staging server gets its own.
- **A folder for backups.** Once a day the app backs up its database and
  uploaded files to a folder you name. A folder on the server's own disk is
  enough to start; a second drive, a NAS, or later a bucket survive more
  ([Back up the database](#back-up-the-database)):

  ```bash
  mkdir -p /srv/backups && chown 1000:1000 /srv/backups
  ```

Check: `ssh root@<server-ip> docker version` prints the server's Docker
version, and `ssh -o PubkeyAuthentication=no root@<server-ip>` is refused with
`Permission denied (publickey)`.

This is the bar for a cloud server, which sits outside your own network and
has a provider console to recover it. A machine you run yourself needs more:
[Hardware you run yourself](#hardware-you-run-yourself).

### 2. Configure `config/deploy.yml`

[Forking](forking) already had you rename `service:`, `image:` and the volume.
Now set the server, the domain and the architecture:

```yaml
servers:
  web:
    hosts:
      - <your-server-ip>     # was: 192.168.0.1 — exactly one; see above

proxy:                       # ships commented out; uncomment it
  ssl: true
  host: app.yourdomain.com

builder:
  arch: amd64                # or arm64, to match the server

volumes:
  - "modelrails_base_storage:/rails/storage"
  - "/srv/backups:/backups"    # the folder from step 1

env:
  clear:
    RAILS_HOST: app.yourdomain.com
    BACKUP_PATH: /backups
```

- **`proxy:`** turns on HTTPS. A deploy without it reports healthy while
  nobody can reach the site ([SSL configuration](#ssl-configuration-paired-changes-required)).
- **`RAILS_HOST`** is the host every email link is built from. Production
  refuses to boot without it ([Production preflight](#production-preflight)).
- **`BACKUP_PATH`** is where the folder from step 1 appears inside the
  container. Without it production still boots, and its log says backups are
  off ([Back up the database](#back-up-the-database)).
- **`registry:`** stays as shipped. `localhost:5555` is Kamal's local
  registry: Kamal runs a registry on the machine doing the deploy, and the
  server pulls the new image from it through the deploy's SSH connection. No
  registry account or password is involved, but the deploying machine needs
  Docker running, since it builds the image too. Building `amd64` on an
  Apple-silicon Mac works through emulation and is slow; `builder.remote`
  builds on the server instead ([Hardware you run yourself](#hardware-you-run-yourself)).

### 3. Set secrets

With the shipped local registry, a deploy needs one secret: `RAILS_MASTER_KEY`,
the key that decrypts the production credentials. The template uses
per-environment credentials, so the key is `config/credentials/production.key`,
not the single `config/master.key` a default `rails new` would use. If you
haven't made the production credentials yet, do it now
([Forking](forking#bootstrap-secrets-and-configuration)):

1. `bin/rails credentials:edit --environment production` creates the key and
   the encrypted file.
2. Paste in the block `bin/rails db:encryption:init` prints. Production
   refuses to boot without it.
3. Commit `config/credentials/production.yml.enc`. Kamal builds the image from
   a clone of the commit, so anything uncommitted never reaches the server; the
   key stays out of git.

`.kamal/secrets` takes `RAILS_MASTER_KEY` from the deploying environment when it
is set and not blank, which is how CI passes it, and otherwise reads the key
file, so your laptop deploys with nothing to set.

**Back the key up in a password manager now.** Without it nobody can decrypt
the credentials, and the encrypted file in git is useless. When a second person
needs it, don't send it in chat: follow
[More than one person deploys](#more-than-one-person-deploys).

That is all step 3 asks of you. The rest is for a secret you add later, such as
a registry token. **`.kamal/secrets` is tracked in git, so it holds a reference,
never a credential.** Kamal reads that file (and its `-common` /
`.<destination>` siblings) with dotenv plus inline command substitution, so
every value resolves at deploy time:

```bash
# From the environment of whoever runs `kamal deploy` — CI provides these
# from its own secret store.
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD

# Or fetched from a password manager at deploy time.
KAMAL_REGISTRY_PASSWORD=$(op read op://YourVault/ghcr/token)
```

`spec/code_smells/kamal_secrets_hold_no_literals_spec.rb` fails the suite if
a literal appears, naming the key but never printing the value. Where the value
itself lives, in order of preference:

1. **A password manager**, read inline with `$(...)`. Nothing lands on disk.
2. **Your CI platform's secret store** (GitHub Actions secrets), exported into
   the deploy job's environment.
3. **An exported shell variable**, if you must — but keep it out of your shell
   profile. Anything exported there is inherited by *every* process you launch
   and shows up in process-environment dumps.

#### Credentials per deploy

Only a staging destination needs this. A staging deploy runs
`RAILS_ENV=production`, so by default it would decrypt
the production credentials, mail login included. `RAILS_CREDENTIALS_ENV=staging`
switches it to `config/credentials/staging.yml.enc` with `staging.key`, whose
value is then that deploy's `RAILS_MASTER_KEY`. Unset, nothing changes. The
staging destination, `config/deploy.staging.yml`, sets it, and
`.kamal/secrets.staging` reads `staging.key` the way `.kamal/secrets` reads
production's. That destination also keeps its own storage volume, so staging
can share production's host without sharing its databases. Give it its own
`proxy.host` and `RAILS_HOST` there too, such as `staging.yourdomain.com`;
otherwise it inherits production's. Sharing a host has one cost: staging's
deploy key logs in to the same root as production's, so anyone who can deploy
staging can reach production. When those aren't the same people, give staging
its own server. Create the credentials file through the same switch:

```bash
RAILS_ENV=production RAILS_CREDENTIALS_ENV=staging bin/rails credentials:edit
```

Commit `staging.yml.enc` beside `production.yml.enc`: Kamal builds the image
from a clone of the commit, and only the keys stay out of git.

`bin/rails credentials:edit --environment staging` refuses here: it boots a
`staging` Rails environment, and the template has none. Give staging your mail
provider's sandbox or test stream as its `smtp` login, so it never mails a
real user.

> A root `.env` does **not** reach Kamal. Kamal's dotenv parses its own secrets
> files, not `.env` — that file is for local Rails only.

### 4. Configure outbound mail

Sign-in is an email. Magic links, invitations and password resets all leave
the box through Action Mailer, so a deployment with no mail server boots,
reports healthy at `/up`, and nobody can sign in. The preflight guard refuses
that boot, which is why this step sits before the first deploy.

Mail leaves over SMTP. Where it goes comes from the environment and how it
signs in comes from the credentials, which keep every app-runtime secret.
Every provider named below speaks SMTP, so moving between them is a change of
values, never of code:

| Setting | Where | Meaning | Default |
| --- | --- | --- | --- |
| `SMTP_ADDRESS` | environment | The provider's SMTP host | none; the guard refuses `localhost` and placeholders |
| `SMTP_PORT` | environment | Submission port | `587` |
| `smtp.user_name`, `smtp.password` | credentials | The provider's login | none; the guard refuses a blank one |
| `SMTP_DOMAIN` | environment | The HELO domain | `RAILS_HOST` |
| `MAIL_FROM` | environment | The sender on every message | `noreply@RAILS_HOST` |

`config/deploy.yml` already carries the Postmark host under `env.clear`. The
login travels inside the encrypted credentials, so `.kamal/secrets` and the
deploy job never hold it. A send that could not reach the server (a connect
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
3. Put the token in the production credentials twice, as both halves of the
   login, then deploy:

   ```yaml
   # bin/rails credentials:edit --environment production
   smtp:
     user_name: <server-api-token>
     password: <server-api-token>
   ```

`SMTP_ADDRESS` is already `smtp.postmarkapp.com` and the port `587`. Messages go
to the server's default transactional stream.

#### Amazon SES over SMTP, the second recipe

The path when a fork needs an EU region, a BAA, or volume pricing. Same six
settings; the differences are where the values come from.

1. In the region you want, verify the sending domain (Easy DKIM publishes the
   DNS records for you).
2. Create **SMTP credentials** from the SES console and put them in the
   production credentials as `smtp.user_name` and `smtp.password`. They are an
   IAM user's derived SMTP password, not the account's access keys.
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

### 5. Point DNS, then deploy

Point your domain at the server and wait until `dig +short app.yourdomain.com`
prints the server's IP. kamal-proxy asks Let's Encrypt for the certificate on
the first request, which fails until the name resolves to the server.

```bash
bin/kamal setup     # First time only
bin/kamal deploy    # Every deploy after
```

CI verifies your production image builds on every pull request that touches a build input (the `image_scan` workflow's cold build) and on every push to `main` (the `docker_build` workflow; see [Getting Started](/docs/developer/getting-started)), and the pre-push hook runs the same build locally when you change one, so the first time you run `kamal deploy` you're not also debugging Dockerfile issues.

Check: `curl -s -o /dev/null -w '%{http_code}\n' https://app.yourdomain.com/up`
prints `200`, and the site loads in a browser. Then take the first backup by
hand instead of waiting for the night:

```bash
bin/kamal app exec "bin/rails backup:now"      # prints the backup it stored
bin/kamal app exec "bin/rails backup:status"   # names the latest
```

For staging, set its host in `config/deploy.staging.yml`, then
`bin/kamal setup -d staging` and `bin/kamal deploy -d staging`.

Once the app is up, mint the first instance operator, the account that runs
the instance itself — see [Instance operations: Day one](operations#day-one-on-an-invite-only-instance).

### 6. Deploy from CI

This step is optional: until you switch it on, you deploy from your laptop as
in step 5. `.github/workflows/deploy.yml` deploys whatever lands on a branch,
with production and staging switched on separately. Release branches are cut
from `next` by `bin/release cut` ([Releasing](releasing)).

| Merge into | Deploys | Switched on by the repository variable |
| --- | --- | --- |
| `main` | production (`bin/kamal deploy`) | `DEPLOY_PRODUCTION=true` |
| `release/**` | staging (`bin/kamal deploy -d staging`) | `DEPLOY_STAGING=true` |

Until a variable is `true`, its deploy is skipped. Each job runs in the GitHub
environment of the same name (`production` or `staging`). Give each one these
secrets:

- `RAILS_MASTER_KEY`: that environment's key file contents.
- `SSH_PRIVATE_KEY`: a key made for that environment's runner alone, such as
  `ssh-keygen -t ed25519 -f ci-production -N ""`, whose public half goes in
  that server's `~/.ssh/authorized_keys` for Kamal's SSH user. Kept apart from
  yours and from each other, each can be removed on its own.
- `SSH_KNOWN_HOSTS`: the contents of that server's `server.known_hosts` from
  [step 1](#1-prepare-the-server), so the runner never trusts on first use.

**Restrict each environment to its branch.** In the repository's Settings →
Environments, set *Deployment branches and tags* to *Selected branches and
tags*: `main` for `production`, `release/**` for `staging`. The workflow
already picks the environment by branch; the restriction keeps any other
branch or workflow from reading those secrets.

The workflow doesn't run the suite again. The branch rules
([Forking](forking#protect-the-branches)) let a PR merge only after `static`
and `test` pass on an up-to-date branch, and a merge commit then carries the
tree CI tested. Deploys into one environment queue rather than cancel each
other. Every deploy leaves a deployment record with its commit on the
repository's Environments page, which is the answer to "what's live?". To make
the first deploy after switching one on, rerun the skipped run for that
branch's latest push.

The runner reaches the server the way your laptop does, over SSH open to the
internet with keys only. If SSH is reachable only over a private network, the
runner joins that network first: [SSH over a private network](#ssh-over-a-private-network).

## Back up the database

Once a day, `DatabaseBackupJob` makes one file holding the database and the
uploaded files, and stores it in a folder or a bucket. The database copy comes
from SQLite's own `VACUUM INTO`, which takes a consistent copy while the app
keeps writing, and is checked with SQLite's integrity check before it's kept.

Production boots without a destination, so an idea you're still testing can
ship first. Until you set one, the boot log and every scheduled run say
"Backups are off", and `backup:status` says the same. Set one before real
people put real data in.

- **Backed up:** `storage/production.sqlite3`, which holds every account,
  workspace and record, and the uploaded files beside it on the storage volume.
- **Not needed:** the cache and cable databases, which rebuild themselves.
- **An accepted loss:** the queue database. Jobs waiting at the moment of a
  disaster are lost; recurring ones run again on schedule.
- **How much you can lose:** up to a day. `BACKUP_SCHEDULE` takes any schedule
  Solid Queue reads, such as `every hour` or `every day at 4am`, under
  `env.clear` in `config/deploy.yml`. Each backup holds every uploaded file, so
  a frequent schedule multiplies the space a large upload folder takes.
- **The key that opens them:** a backup decrypts only with `production.key`,
  so keep that key in your password manager, off the server.

### Start with a folder

Set `BACKUP_PATH` to a folder the container can write to. Where that folder
lives decides what the backups survive:

| The folder is on | It survives | It doesn't survive |
| --- | --- | --- |
| The server's own disk, such as `/srv/backups` | a bad migration, a deleted record | a dead disk |
| A second drive, or a NAS on your network | a dead server disk | a fire, flood or theft that takes the site |
| A bucket elsewhere ([next section](#move-to-a-bucket-when-the-data-matters)) | losing the whole site | |

On the server, make the folder and let the container's user, uid 1000, write
to it. For a NAS or a drive, mount it there first so it comes back at boot
(NFS or SMB in `/etc/fstab`).

```bash
ssh root@<server-ip> "mkdir -p /srv/backups && chown 1000:1000 /srv/backups"
```

Then pass it into the container and point `BACKUP_PATH` at it in
`config/deploy.yml`:

```yaml
volumes:
  - "modelrails_base_storage:/rails/storage"
  - "/srv/backups:/backups"

env:
  clear:
    BACKUP_PATH: /backups
```

- **Retention:** after each backup the app deletes that deployment's backups
  older than `BACKUP_RETENTION_DAYS`, 30 unless you set it. That means the
  server can delete its own backups, so on a NAS turn on its snapshots, which
  the server can't reach, against someone who breaks in.
- **On the database's disk:** when the folder shares a disk with the database,
  every backup logs a warning and `backup:status` repeats it. The backup still
  runs. That's expected for `/srv/backups`. For a NAS it means the drive isn't
  mounted, and the backups are landing on the server's own disk.

The backups sit in the folder as ordinary files, under `backups/<deployment>/`,
so you can copy them anywhere by hand.

### Move to a bucket when the data matters

A bucket with a different company from your server's survives losing the
whole site. It costs a little each month, which is why it's the second step,
not the first. Remove `BACKUP_PATH`, name the bucket under `env.clear`, and put
its key in `bin/rails credentials:edit --environment production`:

```yaml
env:
  clear:
    OBJECT_STORAGE_BUCKET: yourapp-backups
    OBJECT_STORAGE_REGION: eu-central-003
    OBJECT_STORAGE_ENDPOINT: https://s3.eu-central-003.backblazeb2.com
```

```yaml
object_storage:
  access_key_id: ...
  secret_access_key: ...
```

Production refuses to boot with a bucket that's missing its region or key, or
with both `BACKUP_PATH` and a bucket set.

| Provider | `OBJECT_STORAGE_REGION` | `OBJECT_STORAGE_ENDPOINT` |
| --- | --- | --- |
| Backblaze B2 | the bucket's region, such as `eu-central-003` | `https://s3.<region>.backblazeb2.com` |
| Cloudflare R2 | `auto` | `https://<account-id>.r2.cloudflarestorage.com` |
| Hetzner Object Storage | the location, such as `fsn1` | `https://<location>.your-objectstorage.com` |
| Amazon S3 | the bucket's region, such as `eu-central-1` | leave it unset |

A server you run yourself, such as Garage, usually also needs
`OBJECT_STORAGE_FORCE_PATH_STYLE: "true"`.

- **The key:** scope it as narrowly as the provider allows, to this one bucket
  and, where the provider can, without permission to delete. The app only
  uploads and downloads, so a key taken from the server can't erase the
  history.
- **Retention:** give the bucket a lifecycle rule that deletes objects under
  `backups/` after 30 days, or whatever window you want. The bucket deletes old
  backups, not the app, which is what lets the key go without delete
  permission.

Each backup is `backups/<deployment>/<time>.tar.gz`, and
`backups/<deployment>/latest` names the newest. The deployment is
`production`, or the credentials a deploy runs on (`staging`), so staging can
share the bucket, or the folder, without touching production's backups.

### Check it runs

`bin/kamal app exec "bin/rails backup:status"` names the latest backup, and
its time should be within your schedule, a day by default. A backup that fails
is a failed `DatabaseBackupJob`; the next scheduled run tries again.

### Restore

A restore replaces the live database, so the app stops for it:

```bash
bin/kamal app stop
bin/kamal app exec "bin/rails backup:restore"   # the latest backup
bin/kamal app start
```

To go further back, name a backup from the folder or the bucket's listing:

```bash
bin/kamal app exec "bin/rails 'backup:restore[backups/production/2026-11-01T020005Z.tar.gz]'"
```

The restore checks the backup's database with SQLite's integrity check before
it touches anything. It then brings back any uploaded file that's missing, and
moves the current database aside, with its WAL files, as
`production.sqlite3.before-restore-<time>`, so a restore can itself be undone.
Delete that file once you're sure.

The same restore moves an app to a new server: deploy there, copy a backup
into its folder under the same name, and restore it by that name.

**Practise a restore before you need one.** Run it once on staging or a
throwaway server, and write down the date. A backup nobody has restored is
a hope, not a backup.

## More than one person deploys

Once a second person deploys, the production key has to reach them, and it
has to stop working for them when they leave. Sending the key file in chat
does the first and can never do the second. The template's pattern for this
is [fnox](https://fnox.jdx.dev): the deploy secrets live in the repository,
encrypted, and each person and each CI runner decrypts them with a key of its
own.

Rails credentials don't change; they stay the source of truth for everything
the app reads at runtime. fnox holds only what a deploy needs from outside
them: the production key, staging's key, and a registry token if you have one.
Three words carry the rest of this section:

- **Identity**: your private key, `~/.config/fnox/age.txt`. It never leaves
  your machine; back it up in a password manager.
- **Recipient**: the public half of an identity, listed in `fnox.toml`. Every
  value is encrypted to every recipient.
- **Runner**: a CI job that deploys. It gets an identity of its own.

The template ships no `fnox.toml`, because one would carry another app's
recipients and ciphertext into every fork. Git and Docker already ignore
`fnox.local.toml` and `age.txt`.

### Set it up

The first person installs the tools and makes an identity:

```bash
mise use fnox age && mise lock fnox age
mkdir -p ~/.config/fnox
age-keygen -o ~/.config/fnox/age.txt    # prints your recipient, age1…
fnox init --skip-wizard
```

Replace the new `fnox.toml` with two recipient lists, one per environment.
Everyone who can decrypt a value under one provider can decrypt all of them,
so production gets a provider of its own: then a staging runner, or someone who
deploys only staging, can never open production's key.

```toml
[providers.age-production]
type = "age"
recipients = [
  "age1…", # you
]

[providers.age-staging]
type = "age"
recipients = [
  "age1…", # you
]
```

Store each key with its provider, pasting the key at the hidden prompt.
`fnox set` writes the ciphertext; a value typed into `fnox.toml` by hand isn't
encrypted.

```bash
fnox set RAILS_MASTER_KEY --provider age-production                  # production.key
fnox set RAILS_MASTER_KEY --provider age-staging --profile staging   # staging.key
```

Then read the key through fnox in `.kamal/secrets`, replacing its
`RAILS_MASTER_KEY` line:

```bash
RAILS_MASTER_KEY=$(fnox get RAILS_MASTER_KEY)
```

and in `.kamal/secrets.staging`:

```bash
RAILS_MASTER_KEY=$(fnox --profile staging get RAILS_MASTER_KEY)
```

Commit `fnox.toml`, `mise.toml`, `mise.lock` and the secrets files. Check:
`fnox check --all` passes, and `bin/kamal deploy` works as before.

### Add someone

1. They pull your fnox commit, run `mise install` and
   `age-keygen -o ~/.config/fnox/age.txt`, and send you the `age1…` line it
   prints. That line is public; chat is fine.
2. You add it, with a comment naming them, to each provider whose environment
   they deploy, and re-encrypt what changed:

   ```bash
   fnox reencrypt --provider age-production
   fnox reencrypt --provider age-staging --profile staging
   ```

3. You commit; they pull and run `fnox check --all`.
4. Add their SSH public key to the server's `~/.ssh/authorized_keys`. If SSH is
   private, invite them to that network too
   ([SSH over a private network](#ssh-over-a-private-network)).

### Add CI

CI gets one identity per environment, so a staging run never holds a key that
opens production:

```bash
age-keygen -o ci-production.txt    # prints the production runner's recipient
age-keygen -o ci-staging.txt       # prints the staging runner's recipient
```

Add each recipient to its own provider and re-encrypt as above. Store the
contents of each file as `FNOX_AGE_KEY`, the variable fnox reads an identity
from, in the matching GitHub environment, then delete both files and the
environments' `RAILS_MASTER_KEY` secrets. In `.github/workflows/deploy.yml`,
add a step before "Set up Ruby", so the Ruby that step installs stays first on
the path:

```yaml
      - name: Install fnox
        uses: jdx/mise-action@82a612c5ab8bcda7cc5db6b7e81a8e7584c3dc6e # v5.2.3
        with:
          install_args: fnox
```

and in the "Deploy" step, swap `RAILS_MASTER_KEY` for the identity, leaving the
rest as it is:

```yaml
        env:
          FNOX_AGE_KEY: ${{ secrets.FNOX_AGE_KEY }}
          DESTINATION: ${{ github.ref_name == 'main' && 'production' || 'staging' }}
```

### Remove someone

1. Delete their recipient from each provider, re-encrypt as in
   [Add someone](#add-someone), and commit.
2. Remove their SSH key from the server, and them from the private network if
   you use one.
3. **Rotate every secret they could read.** Git history keeps the old
   ciphertext, and their identity still opens it. Anyone who could log in to
   the server could also read the values Kamal wrote there. For the production
   key, rotation means new production credentials: a new key, new values for
   the mail login, OAuth secrets and the rest, the new key stored with
   `fnox set`, and a deploy. [Responding to a Secret Exposure](security#responding-to-a-secret-exposure)
   walks through it.

If people come and go often, that rotation is the cost of keeping secrets in
git, and a shared vault fits better.

Whether or not you use fnox, no identity ever goes on the server, and no
decrypted value is printed in a log or CI output. The server does hold the
decrypted values themselves: at each deploy, Kamal writes them to an env file
on it that only root can read.

## Changing the registry

The local registry keeps images on your own machines: the server can pull only
while a deploy holds the SSH connection open. Move to a hosted registry, such
as GitHub's at `ghcr.io`, when you need one of these:

- **A server pulls without a deploy running**, such as a replacement server,
  or a second one.
- **Images kept somewhere you can inspect**, so you can scan them or run the
  exact production image on your laptop to debug it.
- **Your organisation requires it.**

To switch to `ghcr.io`:

1. Create a GitHub token (classic, since GitHub Packages doesn't accept
   fine-grained tokens) with the `write:packages` scope.
2. In `config/deploy.yml`, point the image and registry at it:

   ```yaml
   image: your-github-user/your-app

   registry:
     server: ghcr.io
     username: your-github-user
     password:
       - KAMAL_REGISTRY_PASSWORD
   ```

3. In `.kamal/secrets` and `.kamal/secrets.staging`, add
   `KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD`, or
   `KAMAL_REGISTRY_PASSWORD=$(fnox get KAMAL_REGISTRY_PASSWORD)` after storing
   it with `fnox set`.
4. For CI without fnox, add the token as `KAMAL_REGISTRY_PASSWORD` in each
   GitHub environment, and to the deploy step's `env:` in
   `.github/workflows/deploy.yml`.
5. After the first push, check the package's visibility on your GitHub
   profile's Packages tab.

Check: `bin/kamal registry login` succeeds.

## SSH over a private network

[Step 1](#1-prepare-the-server) leaves SSH open to the internet with keys
only. Two failures still reach it there: a flaw in the SSH server itself, which
anyone can try, and a leaked key, which works from anywhere. Closing SSH to
everything but a private network removes both, at a cost: everyone who
deploys, CI included, joins that network first. It's required for
[hardware you run yourself](#hardware-you-run-yourself) and an upgrade for a
cloud server. This recipe uses Tailscale; WireGuard works too, with more setup.

1. Install Tailscale on the server and on each deployer's machine, and tag the
   server, say `tag:server`.
2. In the admin console's access controls, replace the policy's default
   allow-everything rule. This one lets everyone you've invited (you and each
   deployer) reach everything, and lets CI reach only the server's SSH port:

   ```json
   {
     "tagOwners": {
       "tag:server": ["autogroup:admin"],
       "tag:ci": ["autogroup:admin"]
     },
     "grants": [
       { "src": ["autogroup:member"], "dst": ["*"], "ip": ["*"] },
       { "src": ["tag:ci"], "dst": ["tag:server"], "ip": ["tcp:22"] }
     ]
   }
   ```

   Keep any rules you already rely on.
3. Point `servers.web.hosts` at the server's Tailscale name, and check the
   host key over it as in step 1. That `ssh-keyscan` line is
   `SSH_KNOWN_HOSTS` now.
4. Have CI join on every run. In Tailscale's admin console, create an OAuth
   client with the `auth_keys` scope and the tag `tag:ci`, store its ID and
   secret in each GitHub environment as `TS_OAUTH_CLIENT_ID` and
   `TS_OAUTH_SECRET`, and add this step before "Load the deploy key":

   ```yaml
         - name: Join the tailnet
           uses: tailscale/github-action@064b10558093f38325e838ddea35486bdc6b1d5c # v4.4.0
           with:
             oauth-client-id: ${{ secrets.TS_OAUTH_CLIENT_ID }}
             oauth-secret: ${{ secrets.TS_OAUTH_SECRET }}
             tags: tag:ci
   ```

5. Deploy once over the tailnet from your laptop and once from CI. Only then
   close port 22 to everything else:
   - **A cloud server:** remove 22 from the provider firewall, keeping 80 and
     443. The provider's console is your way back in if you lock yourself out.
   - **A machine on your network:** your router already keeps the internet off
     port 22, but other devices at home can still reach it. Let the host's own
     firewall admit SSH from the tailnet only. This works here because SSH
     isn't a port Docker publishes:

     ```bash
     ufw default deny incoming
     ufw allow in on tailscale0 to any port 22 proto tcp
     ufw allow 80,443/tcp
     ufw enable
     ```

     Run it at the machine's keyboard, so a mistake can't lock you out.

Check: `ssh` to the server's ordinary address, from a machine that isn't on the
tailnet, times out; over the tailnet it still works.

## Hardware you run yourself

A machine at home or in an office can be a deploy target, but it shares a
network with your other devices, and no provider console or firewall stands
behind it. On top of [step 1](#1-prepare-the-server), it meets every item
below.

**SSH arrives over a private network only** ([recipe](#ssh-over-a-private-network)).

**It comes back on its own.** After a power cut, the chain runs power-on, host
boot, VM if there is one, Docker, then kamal-proxy and the app containers
through Docker's restart policies, with nobody logging in. Kamal expects Linux
running Docker Engine under systemd. A VM is fine if it starts at boot without
a user session; a desktop container runtime that needs someone logged in is
not. Two settings make the chain start: the machine's firmware (BIOS) set to
power on when power returns, usually called "Restore on AC power loss", and
Docker enabled at boot, which `systemctl is-enabled docker` confirms. Prove the
chain by pulling the plug and plugging it back in, with no login, and again
after OS or host upgrades. Full-disk encryption that waits for an unlock breaks the chain, so
choose per host and write down why.

**Its SSH host key never changes unannounced.** On bare metal it doesn't. A VM
built from a cloud image can regenerate its keys whenever its instance ID
changes; if yours does, pin the keys and restore them at every boot. A known-hosts line is a public key, safe
to commit.

**It sits in its own network zone**, such as a separate VLAN or guest network
that can't reach your other devices, and your router forwards only TCP 80 and
443 to it. Your router's documentation covers making the zone; to check it,
`ping` your laptop's address from the server and expect no reply. Two things
can stop the forwarding working. A public IP that changes needs
dynamic DNS, from your router or DNS provider. Carrier-grade NAT, where your
provider shares one public IP across customers, allows no forwarding at all:
you have it when your router's WAN address differs from what
`curl -s https://ifconfig.me` reports. A tunnel service works around both, but
it puts that third party in the TLS path.

**One kamal-proxy serves every app on the host**, each routed by its
`proxy.host`. Its `proxy.run` settings take effect when it boots, so they
belong to the host: keep them the same in every app that deploys there, and
coordinate a change, because applying one means `bin/kamal proxy reboot` for
all of them. With one app and nothing in front, the defaults need no change.
When something in front of the proxy handles HTTPS, such as another web
server or a tunnel, the proxy runs without SSL on other ports:

```yaml
proxy:
  ssl: false
  host: yourdomain.com
  run:
    http_port: 8080
    https_port: 8443
```

With `ssl: false`, kamal-proxy forwards `X-Forwarded-Proto`, and the shipped
Rails settings stay as they are ([SSL configuration](#ssl-configuration-paired-changes-required)).

**Its data is backed up off the machine**, to a bucket elsewhere or to a NAS
or fireproof drive on your network ([Back up the database](#back-up-the-database)).
A copy on the same machine, such as a Garage bucket there, can only ever be a
second copy, since it dies with the machine. A restore has been tested.

**Images are built for its architecture.** When the machine running Kamal
differs, as GitHub's x86 runners do from an arm64 host, either build on the
host itself, by setting `builder.remote` to `ssh://root@<host>` in
`config/deploy.yml`, or build on a runner of the same architecture.

**Self-hosted CI runners, if you use them**, are ephemeral, never run pull
requests from forks, carry their own identity, and never run on the deploy
host.

Adding another app to a host that meets all of this is configuration only:
its own `service`, `proxy.host`, and volume.

## Production-safety invariants

The template ships two Kamal settings that aren't obvious from the Rails scaffold:

### `stop_timeout: 45` at top level

Docker's SIGTERM→SIGKILL grace for a proxied role is 10 seconds. With `SOLID_QUEUE_IN_PUMA: true` (the template default), Solid Queue's `on_worker_shutdown` hook needs longer to drain in-flight jobs before SIGKILL. **45 seconds** is the floor; raise it if you run long-running jobs in-process.

An earlier revision spelled this `stop_wait_time` and paired it with a `max-replicas: 1` docker option — neither is a key Kamal 2 or Docker knows, and `kamal config` rejected the file before touching a host. `spec/code_smells/template_invariants_spec.rb` now runs `config/deploy.yml` through Kamal's own loader, which is the check that catches a misspelled key on the day it is written.

### Builder args pass Ruby version through to the production image

```yaml
builder:
  args:
    RUBY_VERSION: "4.0.9"   # Keep in sync with .tool-versions
```

This ensures `kamal build` always produces an image matching the Ruby version Bundler enforces in `Gemfile.lock`. If `.tool-versions`, `Dockerfile` `ARG RUBY_VERSION`, and `deploy.yml` `builder.args.RUBY_VERSION` ever drift apart, the integration spec at `spec/code_smells/template_invariants_spec.rb` will fail.

## Solid Queue topology

The template ships `SOLID_QUEUE_IN_PUMA: true` in `deploy.yml` env. This runs the Solid Queue **Supervisor inside the web server's Puma process** — one container handles both HTTP requests *and* background jobs.

**This is the right default for the one-box SQLite deploy.** Two containers, one VPS, one `kamal deploy`. No accessory networking. No job-server-can't-reach-SQLite-file issues.

**It is not the right default forever.** Recurring jobs share Puma's GVL with HTTP requests, and a deploy restart can SIGKILL jobs mid-execution if `stop_timeout` is too low.

### Graduation checklist

When you outgrow this default — typically when you add a second web server, or when sustained job volume exceeds ~10 jobs/sec — follow these four steps **in order**:

(The other accessory the template knows is the Hot Cell image-processing sandbox, which runs on the same host as the app and is independent of this checklist: [Hot Cell](/docs/developer/hot-cell).)

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

Steps 2 and 5 of [First deploy](#first-deploy) cover these:

- [ ] Uncomment the `proxy:` block in `config/deploy.yml` and set `host:` to your real domain
- [ ] Point your domain's DNS at the server first — kamal-proxy obtains the Let's Encrypt certificate on demand, which fails if the name doesn't resolve to the host yet
- [ ] Leave `assume_ssl` / `force_ssl` / `ssl_options` in `config/environments/production.rb` as shipped — they are already enabled; there is nothing to uncomment

## Production preflight

`config/initializers/required_production_config.rb` refuses to boot a production process when `RAILS_HOST` is unset or still a placeholder (`example.com`, anything ending in `.example`), when `SMTP_ADDRESS` is unset, `localhost` or a placeholder, or the credentials' `smtp.user_name` or `smtp.password` is blank (see [Configure outbound mail](#4-configure-outbound-mail)), when the Active Record encryption keys are missing from the production credentials, or when a backup bucket is half configured or set alongside `BACKUP_PATH` ([Back up the database](#back-up-the-database)). With no backup destination at all it boots and logs that backups are off. The reason it refuses rather than warns: every mailer link — magic links, password resets, invitations — is generated from `RAILS_HOST`, and DNS-rebinding protection (`config.hosts`) is derived from it. With a placeholder value the app boots, `/up` reports healthy, and nobody can sign in. Missing encryption keys fail the same way — healthy `/up`, then the first read of a user raises. A failed boot is the only version of either failure you can see. Keys: `bin/rails db:encryption:init`, pasted into `bin/rails credentials:edit --environment production` ([Forking](/docs/developer/forking#bootstrap-secrets-and-configuration)).

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

Losing it loses your entire app state. The primary database and the uploaded files are backed up once you set a destination ([Back up the database](#back-up-the-database)); copying a live SQLite file with `cp` is not a backup.

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
bin/kamal redeploy          # Deploy without re-bootstrapping servers or the proxy
bin/kamal redeploy -P       # Same, on the image already pushed (no rebuild)
bin/kamal app containers    # The versions still on the hosts
bin/kamal rollback VERSION  # Boot one of those versions again
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
