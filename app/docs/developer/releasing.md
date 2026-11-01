---
title: Releasing
description: Test your own work first, review a release together on staging, ship it to production as a tagged version, and keep next in step
keywords: release candidate staging production hotfix revert tag next main merge-back review attention removable depends
---

# Releasing

This flow is built around attention. You test your own work as thoroughly as
you like before anyone else spends time on it. On a team, a reviewer
approves each PR's code before it merges; how the PRs behave together is
judged once per release, on staging, where a person's judgment is what's
needed. Production runs a release someone checked, tagged so you can roll back
to it, or a hotfix that couldn't wait for one.

<svg viewBox="0 0 590 582" width="100%" class="hidden md:block" role="img" aria-label="The release flow, following one story, #1487 New onboarding flow. On your branch it is a draft with its hand checks written in the PR, checked by you on your own machine. Merged into next it joins the pile of stories, which deploys nowhere and which CI checks again after every merge. bin/release cut binds next into release/&lt;name&gt;, a book whose page 3 is the story, checked together on staging. bin/release ship publishes it on main, in production, as v2026.10.27, and the version it replaces goes to the archive. main then merges back into next." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs>
    <marker id="arrow-release" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/>
    </marker>
  </defs>
  <rect class="text-accent" x="0" y="0" width="250" height="240" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-info" x="310" y="0" width="250" height="240" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-warning" x="0" y="290" width="250" height="240" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-success" x="310" y="290" width="250" height="240" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <g class="text-surface-raised" fill="currentColor" stroke="none">
    <rect x="40" y="52" width="170" height="132" rx="2"/>
    <rect x="100" y="34" width="50" height="12" rx="3"/>
    <rect x="330" y="44" width="210" height="26" rx="2" transform="rotate(-1 435 57)"/>
    <rect x="330" y="74" width="210" height="26" rx="2" transform="rotate(1 435 87)"/>
    <rect x="330" y="104" width="210" height="26" rx="2" transform="rotate(-1 435 117)"/>
    <rect x="330" y="134" width="210" height="26" rx="2" transform="rotate(1 435 147)"/>
    <path d="M14 336 Q67 328 120 338 L120 478 Q67 470 14 476 Z"/>
    <path d="M120 338 Q173 328 226 336 L226 476 Q173 470 120 478 Z"/>
    <rect x="458" y="372" width="92" height="24" rx="2"/>
    <rect x="454" y="398" width="92" height="24" rx="2"/>
    <rect x="450" y="424" width="104" height="46" rx="3"/>
  </g>
  <rect x="30" y="40" width="190" height="152" rx="6" stroke-width="1.5"/>
  <rect x="40" y="52" width="170" height="132" rx="2" stroke-width="1"/>
  <rect x="100" y="34" width="50" height="12" rx="3" stroke-width="1.5"/>
  <line x1="52" y1="160" x2="198" y2="160" stroke-width="1" stroke-dasharray="3 3"/>
  <rect x="330" y="44" width="210" height="26" rx="2" stroke-width="1.25" transform="rotate(-1 435 57)"/>
  <rect x="330" y="74" width="210" height="26" rx="2" stroke-width="1.25" transform="rotate(1 435 87)"/>
  <rect class="text-info" x="330" y="104" width="210" height="26" rx="2" stroke-width="2" transform="rotate(-1 435 117)"/>
  <rect x="330" y="134" width="210" height="26" rx="2" stroke-width="1.25" transform="rotate(1 435 147)"/>
  <path class="text-info" d="M516 57 L520 61 L528 52 M516 87 L520 91 L528 82 M516 117 L520 121 L528 112 M516 147 L520 151 L528 142" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M14 336 Q67 328 120 338 L120 478 Q67 470 14 476 Z" stroke-width="1.5"/>
  <path d="M120 338 Q173 328 226 336 L226 476 Q173 470 120 478 Z" stroke-width="1.5"/>
  <path class="text-warning" d="M131 437 L135 441 L143 432" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <rect class="text-success" x="330" y="334" width="104" height="136" rx="3" fill="currentColor" stroke="none" opacity="0.18"/>
  <rect class="text-success" x="330" y="334" width="104" height="136" rx="3" stroke-width="2"/>
  <line class="text-success" x1="322" y1="476" x2="442" y2="476" stroke-width="3"/>
  <rect class="text-surface-raised" x="398" y="326" width="46" height="20" rx="2" fill="currentColor" stroke="none" transform="rotate(4 421 336)"/>
  <rect class="text-success" x="398" y="326" width="46" height="20" rx="2" stroke-width="1.5" transform="rotate(4 421 336)"/>
  <rect x="458" y="372" width="92" height="24" rx="2" stroke-width="1"/>
  <rect x="454" y="398" width="92" height="24" rx="2" stroke-width="1"/>
  <rect x="450" y="424" width="104" height="46" rx="3" stroke-width="1.5"/>
  <line x1="252" y1="115" x2="304" y2="115" stroke-width="2" marker-end="url(#arrow-release)"/>
  <path d="M435 242 L435 264 L125 264 L125 284" stroke-width="2" marker-end="url(#arrow-release)"/>
  <line x1="252" y1="410" x2="304" y2="410" stroke-width="2" marker-end="url(#arrow-release)"/>
  <path d="M435 532 L435 546 L578 546 L578 115 L566 115" stroke-width="1.5" stroke-dasharray="5 4" marker-end="url(#arrow-release)"/>
  <g fill="currentColor" stroke="none" font-size="13">
    <text class="text-accent" x="14" y="24" font-size="15" font-weight="700" font-family="ui-monospace, monospace">your branch</text>
    <text x="236" y="24" text-anchor="end">The draft</text>
    <text class="text-accent" x="52" y="72" font-family="ui-monospace, monospace">#1487</text>
    <text x="52" y="92" font-weight="700">New onboarding flow</text>
    <text x="52" y="114">1  Name your workspace</text>
    <text x="52" y="132">2  Invite your team</text>
    <text x="52" y="150">3  Pick a plan</text>
    <text class="text-accent" x="52" y="177">Hand checks in the PR</text>
    <text x="125" y="214" text-anchor="middle">on your machine</text>
    <text x="125" y="232" text-anchor="middle">checked by you</text>
    <text class="text-info" x="324" y="24" font-size="15" font-weight="700" font-family="ui-monospace, monospace">next</text>
    <text x="546" y="24" text-anchor="end">The pile</text>
    <text x="340" y="62"><tspan font-family="ui-monospace, monospace">#1485</tspan> CSV export</text>
    <text x="340" y="92"><tspan font-family="ui-monospace, monospace">#1486</tspan> Who's online</text>
    <text x="340" y="122" font-weight="700"><tspan font-family="ui-monospace, monospace">#1487</tspan> New onboarding</text>
    <text x="340" y="152"><tspan font-family="ui-monospace, monospace">#1488</tspan> Search</text>
    <text x="435" y="214" text-anchor="middle">deploys nowhere</text>
    <text x="435" y="232" text-anchor="middle">checked by CI after every merge</text>
    <text class="text-warning" x="14" y="314" font-size="15" font-weight="700" font-family="ui-monospace, monospace">release/&lt;name&gt;</text>
    <text x="236" y="314" text-anchor="end">The book</text>
    <text x="24" y="360" font-weight="700">Contents</text>
    <text x="24" y="382">1 CSV export</text>
    <text x="24" y="400">2 Who's online</text>
    <text class="text-warning" x="24" y="418" font-weight="700">3 Onboarding</text>
    <text x="24" y="436">4 Search</text>
    <text x="130" y="360">page 3</text>
    <text class="text-warning" x="130" y="380" font-family="ui-monospace, monospace">#1487</text>
    <text x="130" y="398" font-weight="700">Onboarding</text>
    <text x="130" y="422">Hand checks</text>
    <text class="text-warning" x="149" y="442">passed</text>
    <text x="125" y="504" text-anchor="middle">deploys to staging</text>
    <text x="125" y="522" text-anchor="middle">checked together</text>
    <text class="text-success" x="324" y="314" font-size="15" font-weight="700" font-family="ui-monospace, monospace">main</text>
    <text x="546" y="314" text-anchor="end">Published</text>
    <text class="text-success" x="421" y="341" text-anchor="middle" font-weight="700" font-family="ui-monospace, monospace" transform="rotate(4 421 336)">LIVE</text>
    <text x="338" y="368" font-family="ui-monospace, monospace">v2026.10.27</text>
    <text x="338" y="458">4 stories</text>
    <text x="462" y="389" font-family="ui-monospace, monospace">v2026.10.20</text>
    <text x="458" y="415" font-family="ui-monospace, monospace">v2026.10.13</text>
    <text x="502" y="452" text-anchor="middle">archive</text>
    <text x="435" y="504" text-anchor="middle">deploys to production</text>
    <text x="435" y="522" text-anchor="middle">earlier versions archived</text>
    <text x="279" y="105" text-anchor="middle">merge</text>
    <text x="280" y="258" text-anchor="middle" font-family="ui-monospace, monospace">bin/release <tspan font-weight="700">cut</tspan></text>
    <text x="279" y="386" text-anchor="middle" font-family="ui-monospace, monospace">bin/release</text>
    <text x="279" y="400" text-anchor="middle" font-weight="700" font-family="ui-monospace, monospace">ship</text>
    <text x="578" y="572" text-anchor="end">merge-back: the next release starts from what production runs</text>
  </g>
</svg>

<svg viewBox="0 0 340 816" width="100%" class="md:hidden max-w-xs mx-auto" role="img" aria-label="The release flow, top to bottom. Your branch, the draft, checked by you on your own machine. It merges into next, the pile, which deploys nowhere and which CI checks again after every merge. bin/release cut binds next into release/&lt;name&gt;, the book, checked together on staging. bin/release ship publishes it on main, in production, and earlier versions are archived. main then merges back into next." fill="none" stroke="currentColor" font-family="ui-sans-serif, system-ui, sans-serif">
  <defs>
    <marker id="arrow-release-narrow" markerWidth="9" markerHeight="9" refX="6.5" refY="3" orient="auto">
      <path d="M0,0 L8,3 L0,6 z" fill="currentColor" stroke="none"/>
    </marker>
  </defs>
  <rect class="text-accent" x="0" y="0" width="320" height="156" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-info" x="0" y="200" width="320" height="156" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-warning" x="0" y="400" width="320" height="156" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <rect class="text-success" x="0" y="600" width="320" height="156" rx="12" fill="currentColor" stroke="none" opacity="0.1"/>
  <g transform="translate(62 96)">
    <rect x="-32" y="-38" width="64" height="76" rx="4" stroke-width="1.5"/>
    <rect class="text-surface-raised" x="-26" y="-30" width="52" height="62" rx="1" fill="currentColor" stroke="none"/>
    <rect x="-26" y="-30" width="52" height="62" rx="1" stroke-width="1"/>
    <rect class="text-surface-raised" x="-12" y="-42" width="24" height="9" rx="2" fill="currentColor" stroke="none"/>
    <rect x="-12" y="-42" width="24" height="9" rx="2" stroke-width="1.5"/>
    <path class="text-accent" d="M-20 -20 L-6 -20" stroke-width="2" stroke-linecap="round"/>
    <path d="M-20 -10 L16 -10" stroke-width="2" stroke-linecap="round"/>
    <path d="M-20 2 L14 2 M-20 12 L10 12" stroke-width="1"/>
    <path class="text-accent" d="M-20 24 L18 24" stroke-width="1.5" stroke-dasharray="2 2"/>
  </g>
  <g transform="translate(62 296)">
    <g class="text-surface-raised" fill="currentColor" stroke="none">
      <rect x="-36" y="-28" width="72" height="12" rx="1" transform="rotate(-1 0 -22)"/>
      <rect x="-36" y="-12" width="72" height="12" rx="1" transform="rotate(1 0 -6)"/>
      <rect x="-36" y="4" width="72" height="12" rx="1" transform="rotate(-1 0 10)"/>
      <rect x="-36" y="20" width="72" height="12" rx="1" transform="rotate(1 0 26)"/>
    </g>
    <rect x="-36" y="-28" width="72" height="12" rx="1" stroke-width="1.25" transform="rotate(-1 0 -22)"/>
    <rect x="-36" y="-12" width="72" height="12" rx="1" stroke-width="1.25" transform="rotate(1 0 -6)"/>
    <rect class="text-info" x="-36" y="4" width="72" height="12" rx="1" stroke-width="2" transform="rotate(-1 0 10)"/>
    <rect x="-36" y="20" width="72" height="12" rx="1" stroke-width="1.25" transform="rotate(1 0 26)"/>
    <path class="text-info" d="M22 -22 L25 -19 L31 -26 M22 -6 L25 -3 L31 -10 M22 10 L25 13 L31 6 M22 26 L25 29 L31 22" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <g transform="translate(62 496)">
    <g class="text-surface-raised" fill="currentColor" stroke="none">
      <path d="M-42 -26 Q-21 -31 0 -24 L0 30 Q-21 25 -42 28 Z"/>
      <path d="M0 -24 Q21 -31 42 -26 L42 28 Q21 25 0 30 Z"/>
    </g>
    <path d="M-42 -26 Q-21 -31 0 -24 L0 30 Q-21 25 -42 28 Z" stroke-width="1.5"/>
    <path d="M0 -24 Q21 -31 42 -26 L42 28 Q21 25 0 30 Z" stroke-width="1.5"/>
    <path d="M-34 -14 L-8 -14 M-34 -4 L-8 -4 M-34 16 L-8 16 M8 -14 L34 -14 M8 -4 L30 -4" stroke-width="1"/>
    <path class="text-warning" d="M-34 6 L-8 6" stroke-width="2" stroke-linecap="round"/>
    <path class="text-warning" d="M8 8 L12 12 L20 2" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
  <g transform="translate(62 696)">
    <rect class="text-success" x="-40" y="-34" width="40" height="58" rx="2" fill="currentColor" stroke="none" opacity="0.18"/>
    <rect class="text-success" x="-40" y="-34" width="40" height="58" rx="2" stroke-width="2"/>
    <line class="text-success" x1="-46" y1="28" x2="6" y2="28" stroke-width="3"/>
    <rect class="text-surface-raised" x="-14" y="-38" width="22" height="9" rx="1.5" fill="currentColor" stroke="none" transform="rotate(4 -3 -33)"/>
    <rect class="text-success" x="-14" y="-38" width="22" height="9" rx="1.5" stroke-width="1.25" transform="rotate(4 -3 -33)"/>
    <g class="text-surface-raised" fill="currentColor" stroke="none">
      <rect x="12" y="-6" width="30" height="10" rx="1"/>
      <rect x="10" y="4" width="30" height="10" rx="1"/>
      <rect x="8" y="12" width="36" height="18" rx="2"/>
    </g>
    <rect x="12" y="-6" width="30" height="10" rx="1" stroke-width="1"/>
    <rect x="10" y="4" width="30" height="10" rx="1" stroke-width="1"/>
    <rect x="8" y="12" width="36" height="18" rx="2" stroke-width="1.5"/>
  </g>
  <line x1="62" y1="158" x2="62" y2="194" stroke-width="2" marker-end="url(#arrow-release-narrow)"/>
  <line x1="62" y1="358" x2="62" y2="394" stroke-width="2" marker-end="url(#arrow-release-narrow)"/>
  <line x1="62" y1="558" x2="62" y2="594" stroke-width="2" marker-end="url(#arrow-release-narrow)"/>
  <path d="M322 696 L332 696 L332 296 L326 296" stroke-width="1.5" stroke-dasharray="5 4" marker-end="url(#arrow-release-narrow)"/>
  <g fill="currentColor" stroke="none" font-size="16">
    <text class="text-accent" x="14" y="28" font-size="18" font-weight="700" font-family="ui-monospace, monospace">your branch</text>
    <text x="306" y="28" text-anchor="end">The draft</text>
    <text x="120" y="80">on your machine</text>
    <text x="120" y="100">checked by you</text>
    <text class="text-info" x="14" y="228" font-size="18" font-weight="700" font-family="ui-monospace, monospace">next</text>
    <text x="306" y="228" text-anchor="end">The pile</text>
    <text x="120" y="280">deploys nowhere</text>
    <text x="120" y="300">checked by CI,</text>
    <text x="120" y="320">after every merge</text>
    <text class="text-warning" x="14" y="428" font-size="18" font-weight="700" font-family="ui-monospace, monospace">release/&lt;name&gt;</text>
    <text x="306" y="428" text-anchor="end">The book</text>
    <text x="120" y="480">deploys to staging</text>
    <text x="120" y="500">checked together</text>
    <text class="text-success" x="14" y="628" font-size="18" font-weight="700" font-family="ui-monospace, monospace">main</text>
    <text x="306" y="628" text-anchor="end">Published</text>
    <text x="120" y="680">deploys to production</text>
    <text x="120" y="700">earlier versions</text>
    <text x="120" y="720">archived</text>
    <text x="78" y="183">merge</text>
    <text x="78" y="383" font-family="ui-monospace, monospace">bin/release <tspan font-weight="700">cut</tspan></text>
    <text x="78" y="583" font-family="ui-monospace, monospace">bin/release <tspan font-weight="700">ship</tspan></text>
    <text x="0" y="788">merge-back: the next release</text>
    <text x="0" y="810">starts from what production runs</text>
  </g>
</svg>

Every PR is a story. On your branch it's a draft only you have read (the
book kind, not a GitHub draft PR). Merged
into `next`, it joins a pile of stories that CI checks again, all together, after every merge.
`bin/release cut` binds the pile into a book on staging, where people read
the stories together for the first time, and `bin/release ship` publishes
it. The version it replaces goes to the archive, tagged, ready to republish
if you need to roll back. [Forking](forking#protect-the-branches) sets up the branch
rules with `bin/branch-rules`, and [Deployment](deployment#6-deploy-from-ci)
switches on the deploys.

| Branch | Deploys to | Checked by | Takes changes from |
| --- | --- | --- | --- |
| your PR's branch | your machine | you, or the agent writing it | your commits |
| `next` | nowhere | CI on every PR and again after every merge, plus a reviewer's approval on a team | feature PRs |
| `release/<name>` | staging | reviewers, working through each PR's notes | its cut from `next`, then fix, revert and hotfix PRs |
| `main` | production | nothing new: it runs the commit staging ran, or a hotfix | release and hotfix PRs |

Working alone, the flow is the same with fewer people in it. `bin/branch-rules
--solo` drops the required approval, staging is optional (leave
`DEPLOY_STAGING` unset), and each release still gets its changelog section,
its tag and a commit to roll back to.

`bin/release` runs each step. Every command takes `--dry-run`.

| Step | Command |
| --- | --- |
| Name the release in the changelog | `bin/release prepare` |
| Cut a release | `bin/release cut` |
| Ship the reviewed commit | `bin/release ship` |
| Merge `main` back after a hotfix | `bin/release merge-back` |

## Before it merges

Test your own work before you ask for anyone else's time. The specs cover
what they can, and CI runs them on every PR. What they can't cover is how a
change looks, reads and feels, so run your branch with `bin/dev` and click
through it. The onboarding flow you just built is easiest to judge now, while
it's the only thing that changed, not on staging next to someone else's
sign-in rewrite.

The PR template asks for three things the release depends on:

- **What the specs can't show.** The checks you made by hand, written as
  numbered steps someone else can repeat: where to go, what to do, what to
  expect. A reviewer works through them on staging, and an agent with a
  browser can follow them as written. If a step could be a system spec,
  write the spec instead: it then runs on every PR without anyone's time.
- **Depends on.** Any unreleased PR this one needs, so both stay in a release
  or come out of it together.
- **A changelog entry.** A file of its own in `changelog.d/`, such as
  `changelog.d/fix-login.md`, with one line saying what changed for someone
  using the app, under a `### Added` or `### Fixed` heading if it fits one.
  Two PRs never edit the same lines, so their entries can't conflict.
  `prepare` turns the files into the release's notes, and refuses a release
  that has none.

An agent writing a PR takes the same path: run the suite, run the app, walk
the steps, then write them into the PR. Steps a person can follow are steps an
agent can follow, and the other way round, so write them once for both.

### Keep each PR removable

> **One story per PR.** A PR is easiest to check, to review and to pull out
> when it does one thing. Keep a refactor apart from the behavior change it
> makes easy, and send it first. Leave the drive-by fix you noticed on the way
> for its own PR. When a PR turns out to hold two stories, split it before
> anyone reviews it. An agent widens a PR as it works unless asked not to, so
> ask it for the one change and read its diff for anything else.

A PR may have to come out of a release ([Hold back a
PR](#hold-back-a-pr)). That's cheap only when it comes out cleanly:

1. It needs no other unreleased PR, or it names that PR under "Depends on".
2. Its migrations only add. Add the new column here, stop reading the old one,
   and drop it in a later release. A reverted PR's migration has already run
   on staging, and an added column left behind breaks nothing.
3. Its backfills and one-off jobs are safe to run twice. A backfill can run on
   staging, come out with its PR, and run again when the PR comes back.

None of this needs tooling of its own, and the template ships none. A fork
that wants it enforced can add strong_migrations (it refuses destructive
migrations), maintenance_tasks (resumable backfills) or a feature flag gem such
as Flipper, which switches a PR's feature off instead of reverting it.

## Prepare the changelog

```bash
bin/release prepare
```

PRs add their entries as files in `changelog.d/`. `prepare` opens a PR into
`next` that gathers them, with any lines still under `## [Unreleased]` in
`CHANGELOG.md`, into a section for the release, such as `## v2026.10.27`,
and deletes the files. It folds repeated `### Added` / `### Fixed` / ...
subsections into one each, keeps an empty `[Unreleased]` above the new
section, drops subsections with no entries, and turns on auto-merge, so the
PR lands once its checks pass and any approval the rules require is given. It
commits through a temporary index, so your checkout is never touched. It
refuses while a release it named earlier hasn't shipped yet. A fork can have
it run itself once staging is free ([When a release starts](#when-a-release-starts)).

The naming happens on `next`, before the cut, so that work merged during
review adds new entries that wait for the next release. Naming on the release
branch instead would collide with them at the merge-back.

**A release is named for the day.** A second one the same day becomes
`2026.10.27-2`, then `-3`. The script skips any name already used by a tag or
a release branch. Only one release is open at a time (see below), so the
second one starts after the first has shipped.

**In a fork, the template's releases count as shipped.** A fork's changelog
carries the template's release sections, but only the template tagged them.
So `bin/release` also reads the tags of the template that `.fork.yml` names.
A section counts as shipped when the template tagged it on a commit already
in `next`. A release the fork names itself never takes a name the template
has used. If the template is private and the token can't read it,
`bin/release` stops and says so.

**A shipped release's notes don't change.** CI runs `bin/release check`, which
fails a PR that adds, removes or edits a line in a release section that has
been tagged, and names the line. A late line belongs in a new file in
`changelog.d/`, and ships with the next release.

## Cut a release

```bash
bin/release cut
```

Run it once the changelog PR has merged. The release is `next` as it stood
the last time no changelog entry was waiting, in `changelog.d/` or under
`[Unreleased]`: the commit that named the release, or a later one if the PRs
merged since added no entry. The first PR that adds one waits for the next
release, its file still in `changelog.d/`, and `cut` says how many commits
wait. However long after
`prepare` you run it, the code in a release matches its "What ships".

`cut` pushes that commit as `release/<name>`, which deploys to staging, and
opens the release PR into `main` from the release template. The PR body names
the branch, and its "What ships" section is that release's changelog section.

A PR that merged while the changelog PR was still open can leave its entry
waiting when the release was named, though its code is in the release. `cut`
then refuses and lists those entries. Move them under `## v<name>`, deleting
their files, with a PR into `next`, and run `cut` again.

**Only what CI passed.** CI runs on every push to `next`, and `cut` refuses
until it has passed on the commit it would cut. If it failed there, fix it by
a PR into `next` with its changelog line under `## v<name>`, so this release
takes the fix, then run `cut` again. A file in `changelog.d/` would leave the
fix waiting for the next release, and `cut` would pick the failing commit again.

**One release at a time.** `cut` refuses while another `release/*` branch is
open, because staging runs one build and a second candidate would replace the
one under review. It also refuses until `main` is in `next`, meaning the last
merge-back has landed, so the release PR doesn't start out of date. It refuses
a release that already shipped, too.

## Review on staging

Review on staging, not on the PR's diff. The release PR's Commits tab names
every PR in the release; work through each one's "What the specs can't show"
steps. A fix for
something found in review goes into the release branch by PR, and staging
redeploys. A fix that `next` also needs reaches it through the merge-back.

When review approves, record the commit staging is running in the PR's
"Commit reviewed on staging" field. The repository's Environments page shows
it on the latest staging deployment. With staging switched off
(`DEPLOY_STAGING` unset, common for a solo project), review the release
branch however you test, and record its head commit (`git rev-parse
origin/release/<name>`).

A fix made on the release branch puts its changelog line under that release's
`## v<name>` section, not in a file in `changelog.d/`. A file there would
reach `next` with the merge-back and be listed again in the next release.

On a repository whose rules require an approval, someone other than the
author approves the release PR on GitHub before `ship`. That's separate from
the stakeholders' sign-off on staging.

### Hold back a PR

When some of the changes aren't ready, revert them on the release branch, by
PR, and ship the rest:

```bash
git switch -c hold-back-search origin/release/2026.10.27
git revert -m 1 <the feature's merge commit>
# also delete its line from the release's CHANGELOG.md section
git push -u origin hold-back-search
gh pr create --base release/2026.10.27 --title "Hold back search for this release"
```

A squash-merged PR has no merge commit, so revert its squash commit instead:
`git revert <its squash commit>`.

List each held-back PR and its revert commit under "Held back".

**The revert reaches `next` too.** After the release merges back, the held-back
feature is gone from `next` as well. To bring it back, revert the revert on
`next` by PR (`git revert <the revert commit>`), and put its changelog entry
back in a file in `changelog.d/`. Don't re-merge the feature branch: git sees its
commits as already merged, so nothing comes back.

## Ship it

```bash
bin/release ship
```

It finds the release PR waiting to ship and the commit staging's last
successful deploy ran, shows you both, and asks before it ships:

```text
== Ship v2026.10.27 in me/app ==
  PR #42, release/2026.10.27 into main, at abc1234: the commit staging's last deploy ran
Ship abc1234? [y/N]
```

It refuses when the branch has moved past what staging ran, since that commit
hasn't been reviewed. Where staging deploys are off, it offers the branch's
head and says no staging deploy was found. To name them yourself, or where
there's no terminal to answer on, as in CI, pass both:
`bin/release ship <release PR> <commit reviewed on staging>`. A short commit
ID is enough; it must be the PR's head.

It does three things:

1. Merges with `--match-head-commit <commit>`, so only the reviewed commit
   ships. If the branch moved after review, GitHub refuses ("Head branch was
   modified"), and the new commit gets reviewed on staging first. The merge
   deploys production, and the release branch is deleted.
2. Publishes a GitHub Release, `v<name>`, at the merge commit, with that
   release's changelog section as its notes. Publishing creates the tag.
3. Merges `main` back into `next`, as below.

If any step stops partway, run the same command again. It skips the merge
when the PR is already merged, skips publishing when `v<name>` exists, and
reuses a merge-back branch and PR that are already open.

If the PR was merged on GitHub instead, `ship` still checks the merge. It
refuses to publish when the merged branch wasn't at the commit it ships.

## Merge main back into next

`ship` does this itself. After a hotfix, run:

```bash
bin/release merge-back
```

It pushes a branch from `main` (`merge-back/<name>`, or
`merge-back/main-<commit>` after a hotfix), opens its PR into `next`, brings
it up to date, and turns on auto-merge with a merge commit. If GitHub can't
bring it up to date, it says so. A PR whose
head is `main` itself can't be brought up to date, since that would push to
`main`, which is why a separate branch is needed. If `next` moves again before
the PR merges, press Update branch. Keep it **a merge commit**: a squash or
rebase leaves `main` out of `next`'s history, so every later release PR shows
changes `main` already has, and can conflict on them.

## When a release starts

By hand, a release starts when someone runs `bin/release prepare`. A fork can
have it start whenever staging is free instead, so nothing waits in `next`
longer than one review on staging. Add a `RELEASE_TOKEN` secret (below), set
the `AUTO_RELEASE` repository variable to `true`, and
`.github/workflows/next_release.yml` takes the first two steps itself:

1. When any PR merges into `next`, it runs `bin/release prepare --if-needed`.
   That names a release only if none is under way and a changelog entry is
   waiting; otherwise it says why and stops. So a release starts when
   the last one's merge-back lands, or with the first PR after a quiet spell.
2. When CI finishes on `next`, it runs `bin/release cut --if-needed`, which cuts
   a release once one is named, deploying it to staging and opening its PR.
   If CI failed where the release would be cut, the run fails and says so,
   and GitHub tells whoever merged. Re-run a flake's failed jobs, or merge a
   fix with its changelog line under the release's section; the cut follows
   once CI passes.

Reviewers hear about it once, from the release PR. Shipping stays a person's
call: `bin/release ship` asks before it ships the commit staging ran.
PRs from forks of this repository start nothing, since GitHub withholds the
token from them; the next merge from a branch here, or `prepare` by hand,
starts the release.

### Set up the release token

The workflow needs its own token because GitHub runs no workflows on pull
requests opened with a workflow's built-in token, so the changelog PR's checks
would never start and it would never merge. With `AUTO_RELEASE` on and no
token, each run stops at its first step with "RELEASE_TOKEN isn't set".

1. On GitHub, open **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. Under **Repository access**, choose **Only select repositories** and pick
   this repository.
3. Under **Permissions**, set **Contents** and **Pull requests** to **Read and
   write**. Add **Workflows** too if GitHub later refuses a push that carries
   workflow changes.
4. Choose an expiry, and note it. An expired token still counts as set, so
   the run gets past that first check and fails at its `bin/release` step
   instead; releases stop starting on their own until you replace it.
5. Generate it, then store it as the secret. The command asks for the token,
   so it stays out of your shell history:

   ```bash
   gh secret set RELEASE_TOKEN --repo <owner>/<repo>
   ```

6. Turn it on:

   ```bash
   gh variable set AUTO_RELEASE --body true --repo <owner>/<repo>
   ```

Paste the token only into that prompt. A token left in a file, an editor tab
or a chat can be read by anything that sees it; if that happens, revoke it on
the same settings page and make a new one.

## Hotfix

A fix production can't wait a release for goes straight to `main`:

```bash
git switch -c hotfix/sign-in-loop origin/main
# fix, commit, push
gh pr create --base main --title "Sign-in no longer loops after a password reset"
```

Merging it deploys production. A hotfix ships untagged: put its changelog
entry in a file in `changelog.d/`, and the next release lists it under that
release's tag. Until then, rolling back to the last tag rolls back the hotfix
too.

Then run `bin/release merge-back`. If a release branch is open, bring the fix
into it through a branch from `main` with a PR into `release/<name>`.

## In case of emergency

The rulesets give no one a bypass, admins included. When production is down
and the PR path can't carry the fix (CI itself is broken, say), an admin
switches the blocking ruleset off, pushes, and switches it back on:

```bash
gh api 'repos/{owner}/{repo}/rulesets' --jq '.[] | "\(.id) \(.name)"'
gh api -X PUT 'repos/{owner}/{repo}/rulesets/<id>' -f enforcement=disabled
git push origin hotfix/sign-in-loop:main
bin/branch-rules   # add --solo if the repo runs solo; turns every ruleset back on
```

Rerunning `bin/branch-rules` puts back every ruleset exactly as
`config/github/rulesets/` describes it. Then merge `main` back into `next` as
after any hotfix. A ruleset left disabled is the risk here, so rerun the
script in the same sitting as the push.

## Where this is heading

The release round spends reviewers' time, so the aim is to need it less. A
problem a reviewer finds by hand that a spec could have caught becomes a spec,
and the "What the specs can't show" lists get shorter. Once most releases pass
staging untouched, a fork can loosen the flow a step at a time:

1. Ask for an approval only on PRs that touch risky paths, such as sign-in,
   authorization, tenancy and migrations. List them in a `CODEOWNERS` file,
   set `require_code_owner_review` to `true` in `config/github/rulesets/`,
   and drop `required_approving_review_count` to `0`. That combination isn't
   tested here: confirm on a scratch repository that GitHub still asks for the
   code owner's approval before you rely on it.
2. Skip staging for releases that touch none of those paths.
3. Run `ship` from CI too, once the release PR's checks pass. `cut` already
   runs from CI when `AUTO_RELEASE` is on.

The last step is where [Impatient
Programming](https://impatientprogramming.org/rules/#rule-27) points: green
merges itself. The tags, the changelog and rollback by commit stay the same at
every step.

## What makes it run

Four kinds of lever move a release along.

**`bin/release` does the work.** It runs the [release_flow](https://github.com/dschmura/release_flow)
gem, which wraps `git` and the GitHub CLI: `prepare`
names the release in the changelog and opens that as a PR into `next`, `cut`
pushes `release/<name>` and opens its PR into `main`, and `ship` merges it,
tags it and opens the merge-back. A person and a workflow run the same
commands, so automating a step changes who runs it, not what it does.
Each command names the repository it acts on in its first line.

Run by hand, its pushes go through your pre-push hook, except a commit
already on origin: `cut` pushes a commit on `next`, the merge-back one on
`main`, and both passed CI's required checks on their way there. `cut`
only cuts a commit whose CI run passed, and every branch it pushes lands
through a PR whose required checks run again. If a push fails, it shows the
end of what the hook said and saves the rest to `tmp/release-push.log`.

**Workflows react to events.** Each file in `.github/workflows/` names the
event that starts it:

| Workflow | Starts when | Does |
| --- | --- | --- |
| `ci.yml` | a PR opens or updates; a push to `next` or `main` | runs the checks |
| `deploy.yml` | a push to `release/**` or `main` | deploys: release branches to staging, `main` to production |
| `next_release.yml` | a PR merges into `next` | `bin/release prepare --if-needed` |
| `next_release.yml` | CI finishes on a push to `next` | `bin/release cut --if-needed`, which fails loudly if CI failed |

One step's output is the next one's event. `cut` pushing a release branch is
what deploys staging, and the changelog PR merging is a push to `next`, which
runs CI, whose passing starts the cut.

**GitHub's PR features keep it moving.** Auto-merge lands the changelog and
merge-back PRs once their checks pass, and once approved where the rules ask
for an approval. The branch rules from `bin/branch-rules` make every change to
`next`, `release/*` and `main` a PR with passing checks, and delete branches
once they merge, which is how `bin/release` tells that a release is still
under way: its branch still exists.

**Repository settings are the switches.** `DEPLOY_STAGING` and
`DEPLOY_PRODUCTION` turn on the deploys, and `AUTO_RELEASE` turns on
`next_release.yml`. `RELEASE_TOKEN` is the token that workflow acts with,
because GitHub runs no checks on a PR opened with a workflow's built-in token,
so the changelog PR would never merge.

With every switch on, one release runs like this:

1. A PR merges into `next`. CI checks `next`, and prepare names a release if
   staging is free and something is waiting.
2. The changelog PR merges itself. CI checks `next` again.
3. CI passes, so the cut pushes `release/<name>`, staging deploys it, and the
   release PR opens.
4. A person reviews it on staging and runs `bin/release ship`. Production
   deploys, the merge-back merges itself, and that merge starts step 1 for the
   next release.

Step 4 is the only one that needs a person, apart from approvals on a team.

## Changing the flow

The flow is a default, not a requirement. The branch rules live in
`config/github/rulesets/`, the checks in `.github/workflows/ci.yml` (which
`bin/release cut` reads by name), the deploys in `.github/workflows/deploy.yml`, the
automatic start in `.github/workflows/next_release.yml`, the
steps in the release_flow gem behind `bin/release`, and this page, the release template in
`.github/PULL_REQUEST_TEMPLATE/release.md` and the PR template in
`.github/PULL_REQUEST_TEMPLATE.md` describe them. Change all of them
together.

`bin/release` takes its names from `.release_flow.yml` at the repository's
root. A setting the file leaves out takes the gem's default:

| Setting | Here | What it names |
| --- | --- | --- |
| `integration_branch` | `next` | the branch PRs merge into |
| `production_branch` | `main` | the branch production deploys |
| `ci_workflow` | `ci.yml` | the workflow `cut` waits on |
| `staging_workflow` | `deploy.yml` | the workflow whose deploys `ship` reads |
| `guide` | `/docs/developer/releasing` | the page `bin/release --help` points to |
| `template` | from `.fork.yml` in a fork | the GitHub repository this one forks, as `owner/repo` |

A setting it doesn't know stops `bin/release` with the list of those it
does. The workflow `next_release.yml` and the branch rules name the branches
too, so rename them there as well.

The changelog and release-name convention is separate from the flow. It lives
in the gem's `ReleaseFlow::Changelog`, and the flow reads it only through
that module's public methods. A fork that keeps its changelog another way
reopens that module in `bin/release`, after `require "release_flow"`, and
keeps the method signatures. In a fork, `bin/release` reads the template
from `template_url` in `.fork.yml`, which `bin/fork` writes, unless
`.release_flow.yml` names one.
