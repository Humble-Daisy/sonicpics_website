---
title: Background Jobs
description: Solid Queue topology, named queues, recurring jobs, and the graduation path from in-Puma supervisor to dedicated bin/jobs host.
keywords: solid queue jobs mailers default low recurring digest cron observability mission control queue routing
---

# Background Jobs

This template uses **Solid Queue** as its background job backend — the Rails 8 default. Jobs persist to SQLite (the same database that holds your app data, separated by Active Record's multi-DB support).

> **Design rationale:** queue topology decisions on this page came out of an Ops panel review.

## Where jobs run

By default — and **per the template's design** — Solid Queue runs **inside the web server's Puma process**. The `SOLID_QUEUE_IN_PUMA: true` setting in `config/deploy.yml` activates the `puma-plugin-solid_queue` plugin, which starts the Supervisor as part of Puma's boot.

This means:

- **One container** handles HTTP requests *and* background jobs
- **One image deploy** updates both
- **No accessory networking** for the job runner
- **No SQLite-can't-reach-the-other-host problem**

It's the right default for a SQLite + one-VPS template. When you outgrow it, see [Graduation to a dedicated jobs host](#graduation-to-a-dedicated-jobs-host) below.

## Named queues (for observability)

`config/queue.yml` declares three named queues instead of the `queues: "*"` wildcard:

```yaml
workers:
  - queues: [ default, mailers, low ]
    threads: 3
    processes: <%= ENV.fetch("JOB_CONCURRENCY", 1) %>
    polling_interval: 0.1
```

**Why named queues?** With a single worker process + 3 threads sharing the GVL, splitting queues *doesn't* relieve contention — that's a multi-process win, not a multi-queue win. What named queues *do* give you is **observability**: when a queue backs up, you can see which class of work is slow.

| Queue | Convention | Examples |
|---|---|---|
| `default` | Business logic, model callbacks, the notifier sweeps, anything you `perform_later` without specifying a queue | `WorkspaceInvitationExpiringSweepJob`, `WorkspaceCapacitySweepJob`, `NotificationDispatchReconcileJob`, custom callback jobs |
| `mailers` | Action Mailer / mailer-class jobs (network-bound, slower) | `DigestMailerJob`, `UserMailer.deliver_later` |
| `low` | Best-effort cleanup and retention sweeps — nobody is waiting on it, and it must never delay work someone *is* waiting on | `clear_solid_queue_finished_jobs`, `NotificationCleanupJob`, `ExpiredSessionsSweepJob`, `WebauthnChallengesSweepJob`, `UnattachedBlobsSweepJob`, `ActivityLogRetentionSweepJob` |

### Routing a job to a specific queue

Set `queue_as` in the job class:

```ruby
class DigestMailerJob < ApplicationJob
  queue_as :mailers

  def perform(...)
    # ...
  end
end
```

Or route at perform time:

```ruby
SomeJob.set(queue: :low).perform_later(arg)
```

Mailer jobs from `Mailer.deliver_later` calls automatically use the `mailers` queue if the Action Mailer adapter is configured for it (the Rails default since 8.0).

## Recurring jobs

Recurring jobs are declared in `config/recurring.yml` and dispatched by Solid Queue's scheduler. The template ships ten:

| Job | Cadence | Queue | What it does |
|---|---|---|---|
| `clear_solid_queue_finished_jobs` | Every hour at :12 | `low` | Cleans up completed/failed jobs from Solid Queue's own tables in batches with 0.3s sleep between |
| `workspace_invitation_expiring_sweep` | Every 6 hours | `default` | Notifies users whose invitations expire soon (per-day idempotency) |
| `workspace_capacity_sweep` | Every 12 hours | `default` | Alerts workspace owners approaching member limits |
| `digest_mailer` | Every 15 minutes | `mailers` | Polls the `digest_next_due_at` index to send pending digest emails per each user's cadence |
| `notification_dispatch_reconcile` | Every 15 minutes | `default` | Re-enqueues `Noticed::EventJob` for events whose enqueue never landed — rows committed, `dispatched_at` still NULL between 5 minutes and 24 hours old. On `default`, not `low`: it re-delivers a notification a user is waiting on (#927) |
| `notification_cleanup` | Daily at 3am UTC | `low` | Batched deletion of old notifications (chunks of 100 with SQLite lock release between transactions) |
| `expired_sessions_sweep` | Daily at 4am | `low` | Batched delete of sessions past the idle/absolute timeouts (expiry is already enforced at read time) |
| `webauthn_challenges_sweep` | Daily at 4:30am | `low` | Deletes WebAuthn challenge rows past a 1-day grace, consumed or not |
| `unattached_blobs_sweep` | Daily at 5am | `low` | Purges direct-upload blobs that were never attached, after a 2-day grace |
| `activity_log_retention_sweep` | Weekly, Sunday 3:30am | `low` | Bounds the activity trail at the job's `RETENTION_WINDOW`, minus the security retention floor |

### Why the sweeps are on the `low` queue

Six of the ten entries are pure housekeeping — nothing downstream is waiting on them — so they belong on `low`, where they cannot delay work someone *is* waiting on. Three stay on `default` because they put a notification in front of a user: the two `workspace_*` sweeps dispatch user-facing notifiers, and `notification_dispatch_reconcile` re-delivers one that already failed to arrive.

A recurring entry with **no** `queue:` key is not "the default queue" — Solid Queue resolves it to `SolidQueue::RecurringJob`, whose queue is `solid_queue_recurring`. Nothing in `config/queue.yml` polls that, so such a job enqueues and is never claimed, silently. Always name a queue.

### Why `digest_mailer` is on the `mailers` queue

It's the only currently-shipping recurring job that is **mailer-class work** — network-bound, can be slow due to SMTP timeouts. Routing it to `mailers` gives you a clean operational signal: when the `mailers` queue backs up, you know it's SMTP, not your sweep jobs.

### Adding a recurring job

Append to `config/recurring.yml`:

```yaml
production:
  my_new_job:
    class: MyNewJob
    queue: default     # or mailers / low
    schedule: every 30 minutes
```

Schedule syntax supports `every N seconds/minutes/hours/days`, `at H:Mam every day`, and full cron expressions. See [Solid Queue docs](https://github.com/rails/solid_queue) for the full schedule grammar.

## Mission Control (the job dashboard)

In development you can mount Solid Queue's Mission Control dashboard:

```ruby
# config/routes.rb (if not already present)
mount MissionControl::Jobs::Engine, at: "/jobs" if Rails.env.development?
```

In production, mount it behind Pundit authorization so only admins can see it. The dashboard shows per-queue throughput, in-flight jobs, failures, and retries — invaluable for debugging "why is X queue backed up?"

## Configuration knobs

| Setting | Default | Where | When to change |
|---|---|---|---|
| `JOB_CONCURRENCY` | `1` | `config/deploy.yml` env.clear | Increase only after migrating off `SOLID_QUEUE_IN_PUMA: true` — additional processes can't all run inside Puma |
| `threads: 3` | 3 | `config/queue.yml` | Lower to `2` if you measure SQLite write-lock contention; higher buys little because the GVL serializes Ruby work anyway |
| `polling_interval: 0.1` | 100ms | `config/queue.yml` | Lower = more responsive job pickup, more CPU spent polling. The default is fine for nearly all workloads |
| `dispatchers.batch_size: 500` | 500 | `config/queue.yml` | Tune up if you have huge backlog dispatch storms; rarely needed |

## Deploy-time behavior

When `kamal deploy` rolls a new container:

1. Solid Queue's `puma-plugin-solid_queue` receives the shutdown signal alongside Puma
2. Its `on_worker_shutdown` hook begins draining in-flight jobs
3. Docker waits `stop_timeout` seconds before SIGKILL (45 in `config/deploy.yml` — see [Deployment](/docs/developer/deployment#stop_timeout-45-at-top-level))
4. Any job that hasn't completed by then gets SIGKILLed and re-runs on the next container (via Solid Queue's at-least-once delivery semantics)

**Jobs you write should be idempotent.** Solid Queue gives you at-least-once delivery; deploys can SIGKILL mid-execution if `stop_timeout` is too tight. Use database constraints, idempotency keys, or `find_or_create_by!` patterns instead of assuming "this job runs exactly once."

## Graduation to a dedicated jobs host

When you outgrow the in-Puma supervisor — typically because:

- Sustained job throughput exceeds ~10 jobs/sec
- You've added a second `web` host (which can't all run separate Solid Queue supervisors against the same SQLite file anyway)
- Recurring jobs are noticeably affecting HTTP p99 latency

…follow the four-step graduation checklist on [Deployment](/docs/developer/deployment#graduation-checklist). The summary:

1. Add a database accessory (Postgres or MySQL)
2. Set `DB_HOST` in `env.clear`
3. Flip `SOLID_QUEUE_IN_PUMA` to `false`
4. Uncomment `servers.job:` in `deploy.yml` and deploy a separate `bin/jobs` supervisor

The same image runs in both `web` and `job` roles — only the `cmd` differs. Mission Control sees both supervisors and aggregates their queue stats.

## Local development

Development runs jobs the way production does: `config.active_job.queue_adapter = :solid_queue`, on the `queue` database. `bin/dev` starts the web server, the Tailwind watcher and `bin/jobs` (from `Procfile.dev`), so jobs, mail and recurring schedules run while it's up, and concurrency limits apply as in production.

**If you start only `bin/rails server`, jobs queue up and nothing works them.** That includes mail sent with `deliver_later`. Use `bin/dev`, or run `bin/jobs` alongside the server.

Action Cable uses Solid Cable in development too, on its own `cable` database. A job runs in `bin/jobs`, a separate process, and Rails' default `async` cable adapter only reaches browsers connected to the process that broadcast. With Solid Cable, a job's Turbo broadcasts reach the page. An existing checkout needs `bin/rails db:prepare` once to create `storage/development_cable.sqlite3`.

If you want to test job processing in isolation:

```bash
bin/jobs   # Runs only the Solid Queue Supervisor, no Puma
```

Useful when you're iterating on a job and don't need web requests in the mix.

## See also

- [Deployment](/docs/developer/deployment) — Kamal topology + the graduation path
- [Notifications](/docs/user/notifications) — User-facing side of recurring `digest_mailer` and friends
- [Notifications (technical)](/docs/developer/notifications) — `Noticed` integration with Solid Queue
- `config/queue.yml` — Worker configuration with inline comments
- `config/recurring.yml` — Schedule declarations
- [Solid Queue GitHub](https://github.com/rails/solid_queue) — Upstream docs and schedule syntax reference
