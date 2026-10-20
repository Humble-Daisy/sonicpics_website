---
title: Hot Cell (Active Storage sandbox)
description: Move Active Storage's image decoding into an unprivileged sibling container, how to turn it on for a fork, verify it, tune it and turn it off
keywords: hot cell hotcell active storage libvips sandbox variant analyzer cve kamal accessory heic image processing
---

# Hot Cell

Active Storage decodes uploaded images with libvips inside the Rails process, to make variants and to read their dimensions. That process holds the app's code, its credentials and its environment. CVE-2026-66066 used exactly that path: a crafted upload read `secret_key_base` back out through a thumbnail.

[Hot Cell](https://github.com/basecamp/hotcell) moves the decoding into a **cell**: a sibling container on the same host with no network, no access to the app's filesystem or environment, no capabilities, and a fresh worker process for every request. A file that exploits libvips lands in a process that holds nothing and is about to be reaped.

The template ships Hot Cell **wired but off**. Nothing changes until a fork sets `HOTCELL_ROOT`; until then Active Storage processes images in the app exactly as before.

## What it protects, and what it doesn't yet

| Decoding path | Off (default) | On |
|---|---|---|
| Variants (avatars, logos, rich-text images) | In the app | In the cell |
| Image analysis (width, height) | In the app | In the cell |
| Previews (PDF, video) | Not installed | Off: `previewers = []`, so a tool later added to the app image can't start decoding there |
| `active_storage_validations` `content_type:` and `size:` | Declared type only, no decoding | Same |

**libvips stays in the app image.** While the cell is off, variants run in the app, so the library has to be there. A fork that has turned the cell on can remove `ruby-vips`, `image_processing` and the apt package from its own `Dockerfile`; Hot Cell's README calls that removal the security improvement. Until then, what the cell buys is that no untrusted byte is decoded in the app process.

The attachment guard (`spec/code_smells/attachments_are_validated_spec.rb`, see [Testing](/docs/developer/testing)) forbids validators that would decode an upload in the app to check it.

## Prerequisites

- **Rails with the variant-processor seam.** `config.active_storage.variant_processor` accepts a class from rails/rails#58384, which is on Rails `main` and unreleased. This template tracks `main`; a fork on a released Rails waits for 8.2.
- **Ruby 3.3 or newer** for the gems; the template runs 4.0.7.
- **A registry the host can pull from.** Kamal doesn't build or deploy accessory images, so the cell image has to be pushed somewhere. The template's default `localhost:5555` registry can't serve an accessory; use GitHub Container Registry or another remote one ([Deployment](/docs/developer/deployment)).

## How it is wired

- `config/initializers/hotcell.rb` is the only switch. It registers the `active_storage` cell and, when `HOTCELL_ROOT` is set, points `variant_processor` and `analyzers` at the Hot Cell classes and sets `previewers` to `[]`. No environment file mentions Hot Cell.
- `hotcell/` is the cell image: `Dockerfile`, `Gemfile` and `Gemfile.lock`, `config.rb` (limits) and `operations/` (what the cell serves). It installs libvips and libheif's HEVC and AV1 decoders by name and nothing else, and its build fails unless libvips registers its HEIF loader.
- A failed variant answers its image request instead of raising: a permanent failure redirects to a placeholder image, and a transient one (a cell restarting or unreachable) answers 503 `no-store`, so the next page view fetches it again ([Security](/docs/developer/security), Image Processing).
- Gates: `hotcell_build` builds the image pre-push when `hotcell/` changes; `bundler-audit check hotcell` audits its gems pre-push and in CI; `hotcell_image_scan.yml` scans it with Trivy; template invariants keep the two lockfiles on one Hot Cell version and the cell's operations equal to what the initializer routes.

## Turn it on

These steps are for a fork's production host. Run them in order.

1. **Build and push the cell image**, tagged with the Hot Cell version (never `:latest`, so a rollback names an image and the running cell is identifiable):

   ```sh
   docker build --pull --platform linux/amd64 \
     --build-arg RUBY_VERSION=$(awk '/^ruby/{print $2}' .tool-versions) \
     -t <registry>/<image>-hotcell:1.2.0 hotcell
   docker push <registry>/<image>-hotcell:1.2.0
   ```

   `--platform` matches `builder.arch` in `config/deploy.yml`; an image built on Apple silicon without it fails on the host with `exec format error`.

2. **Edit `config/deploy.yml`, merging into the keys it already has.** `servers:`, `volumes:` and `env:` are already there: add these lines inside them, and never add a second `volumes:` or `env:`. YAML keeps only the last of two keys with one name, and Kamal then deploys without the storage volume that holds SQLite and the uploads, or without your secrets — and the check in step 3 still passes. `volumes:` is the top-level key (Kamal roles have no `volumes:`). The volume name carries the app's name so two apps on one host never share a socket directory; `bin/fork` renames it with the rest of the file.

   ```yaml
   servers:
     web:
       options:
         group-add: 10001                              # the cell's gid; admits the app to its sockets
   volumes:
     - "modelrails_base_storage:/rails/storage"        # already there: keep it
     - modelrails_base_hotcell_sockets:/run/hotcell/active_storage  # $HOTCELL_ROOT/<cell name>
   env:
     clear:
       # every entry already under env.clear stays, and env.secret stays as it is
       HOTCELL_ROOT: /run/hotcell
       HOTCELL_GROUP: "10001"
   accessories:
     active_storage:
       image: <registry>/<image>-hotcell:1.2.0
       roles: [ web ]
       network: none
       volumes:
         - modelrails_base_hotcell_sockets:/run/hotcell/cell
       options:
         cpus: 2
         memory: 2g
         memory-swap: 2g
         read-only: true
         tmpfs: /tmp:rw,nosuid,nodev,noexec,size=512m
         cap-drop: ALL
         security-opt: no-new-privileges:true
         user: "10001:10001"
         pids-limit: 512
   ```

   `network: none` is an accessory key, not an option: under `options:` Kamal emits a second `--network` and Docker refuses the container. The values come from Hot Cell's [container reference](https://github.com/basecamp/hotcell/blob/master/docs/container.md); `memory` counts every worker and the tmpfs, so keep the tmpfs at 512m with `memory: 2g`.

3. **Check the command before you deploy.** Kamal's merged config doesn't show a doubled flag, so print the command it will run:

   ```sh
   bundle exec ruby -rkamal -e '
     config = Kamal::Configuration.create_from(config_file: Pathname.new("config/deploy.yml"), version: "check")
     puts Kamal::Commands::Accessory.new(config, name: :active_storage).run.flatten.join(" ")'
   ```

   `--network none` must appear exactly once.

4. **Boot the cell, then deploy the app:**

   ```sh
   kamal accessory boot active_storage
   kamal deploy
   ```

5. **Read the app's boot log** (`kamal app logs`). At boot the app asks the cell to describe itself and warns, without failing, about a cell that is unreachable, on another Hot Cell version, slower than the app waits, or in a group the app doesn't hold. With the template's limits the cell answers within 26 seconds and the app waits 30, so no `hotcell` warning lines means the cell answered on the same version with the group held. If you raise `deadline` or `queue_wait`, raise the app's `timeout:` in `config/initializers/hotcell.rb` with them; a template invariant fails when they cross.

6. **Check the running container's flags:**

   ```sh
   docker inspect <cell container> --format '{{json .HostConfig}}' | jq '{
     NetworkMode, ReadonlyRootfs, CapDrop, SecurityOpt, PidsLimit, Memory, MemorySwap, Tmpfs, Binds
   }'
   ```

   Expect `NetworkMode: "none"`, `ReadonlyRootfs: true` and `CapDrop: ["ALL"]`. Hot Cell's [conformance script](https://github.com/basecamp/hotcell/blob/master/bin/conformance) is a pre-deploy image check, not this: it supplies its own flags, so it passes against an image you're about to deploy with `cap-drop` missing.

7. **Re-run analysis for anything the cell couldn't analyze.** A transient failure (the cell restarting or unreachable) is retried by the job, ten times. A permanent one (for example a worker killed for exceeding `memory` while the limits were being tuned) is recorded: Active Storage marks the image analyzed with no dimensions and never retries it ([Hot Cell's codes reference](https://github.com/basecamp/hotcell/blob/master/docs/codes.md), What Active Storage records). After fixing the cause:

   ```ruby
   ActiveStorage::Blob.where("content_type LIKE 'image/%'").find_each do |blob|
     next unless blob.metadata["width"].nil?
     blob.update!(metadata: blob.metadata.except("analyzed"))
     blob.analyze_later
   end
   ```

## Tune it

| Setting | Where | Default | Keep together with |
|---|---|---|---|
| `cpus` | accessory `options:` | 2 | `OMP_NUM_THREADS` in `hotcell/Dockerfile` (default 2): libvips sizes its thread pool from the host's cores, not the quota |
| `memory` | accessory `options:` | 2g | the tmpfs size, and `concurrency × peak worker memory`; above the cell's own `memory` limit |
| `concurrency` | `hotcell/config.rb` | 4 | `pids-limit`, `memory` |
| `deadline` | `hotcell/config.rb` | 20 s | the longest image you accept, and the app's `timeout` |
| `queue_wait` | `hotcell/config.rb` | 5 s | the app's `timeout` |
| `timeout` | `HotCell.register` in `config/initializers/hotcell.rb` | 30 s | stays above `queue_wait + deadline + 1`, or every boot warns and a slow request ends in the app's timeout instead of the cell's answer |

A starting point for a small host (one vCPU, 2 GB RAM), not yet measured: `cpus: 1`, `memory: 1g` with `memory-swap: 1g`, `concurrency: 2`, `OMP_NUM_THREADS=1`. Hot Cell's [tuning guide](https://github.com/basecamp/hotcell/blob/master/docs/tuning.md) has the arithmetic.

## Upgrade it

The app's `hotcell-client` and the cell's `hotcell-server` must run the same version, so Dependabot leaves the Hot Cell gems alone and they move by hand, in one pull request:

1. Bump the version in `Gemfile` and `hotcell/Gemfile`; run `bundle update activestorage-hotcell-client` and, from the repository root, `BUNDLE_GEMFILE=hotcell/Gemfile bundle update hotcell-server activestorage-hotcell-server`. The lockfile-parity invariant fails if they disagree.
2. Compare the gem's `install/*.tt` templates between the two versions and apply what changed to `hotcell/`. Re-running `bin/rails hotcell:install` shows nothing: it skips files that exist.
3. After the pull request merges, build and push the new tag, change the accessory's `image:`, and run `kamal accessory reboot active_storage`. `kamal deploy` never touches accessories.

The cell's other gems (ruby-vips, ffi, …) are audited by `bin/bundler-audit check hotcell` on every push and CI run.

## Add to it

- **An attachment.** Give it `content_type:` and `size:` validations; the attachment guard requires both. Nothing changes in the cell for images.
- **A tool or a custom operation.** Add the apt packages on the reserved `RUN` line in `hotcell/Dockerfile`, not on the template's libvips line, so upstream changes to that line merge cleanly. Put each operation in its own file under `hotcell/operations/`. The operation-parity invariant then asks for the matching client class in `config/initializers/hotcell.rb`. Keep `hotcell/Gemfile` short: every gem in it is inside the blast radius.

## Develop with it

The cell can run on a laptop as a plain process; a containerized cell works only on Linux, because descriptor passing doesn't cross the VM Docker uses on macOS. Install the cell's bundle once (`BUNDLE_GEMFILE=hotcell/Gemfile bundle install`), then add Hot Cell's two lines to `Procfile.dev`:

```procfile
web: HOTCELL_ROOT=$PWD/tmp/hotcell-sockets bin/rails server
cell: BUNDLE_GEMFILE=$PWD/hotcell/Gemfile HOTCELL_CONFIG=$PWD/hotcell/config.rb HOTCELL_OPERATIONS=$PWD/hotcell/operations HOTCELL_DIR=$PWD/tmp/hotcell-sockets/active_storage bundle exec hotcell --development
```

Keep `--development`: without it the cell empties the system temporary directory at boot. Under Docker Desktop the cell logs `cell.ptrace_scope_unknown` at boot, because the VM has no Yama security module; a Linux host has one.

## Turn it off, or recover it

- **Off.** Remove `HOTCELL_ROOT` and `HOTCELL_GROUP` from `env.clear` and `kamal deploy`. The app processes images itself again; the accessory can stay.
- **A cell that can't create its sockets.** If the app's deploy created the socket volume before the cell's first boot, the cell's user may not own it. `kamal accessory remove active_storage`, `docker volume rm modelrails_base_hotcell_sockets` on the host, then `kamal accessory boot active_storage` and `kamal app boot`.
