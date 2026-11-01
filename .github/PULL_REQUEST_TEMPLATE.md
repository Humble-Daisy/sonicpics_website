<!-- Keep this short. Delete any section that doesn't apply. -->

## What & why

<!-- One or two sentences: what this changes and the problem it solves. Link issues with #123. -->

Depends on: <!-- unreleased PRs this one needs, e.g. #123, so they leave a release together. Delete if none. -->

## How it was tested

<!-- The commands you ran and their result. The full RSpec suite must be green before merge. -->

- [ ] Full test suite green (Lefthook pre-push ran the suite locally)
- [ ] New behavior is covered by specs, written failing-first (TDD)

## What the specs can't show

<!-- What you checked by hand with bin/dev, as numbered steps a reviewer (or an agent) can repeat on staging: where to go, what to do, what to expect. If a step could be a system spec, write the spec instead. Delete if nothing. -->

## Checklist

- [ ] Changelog: a file of its own in `changelog.d/` (e.g. `changelog.d/fix-login.md`), one line saying what changed for someone using the app
- [ ] Removable from a release: no unreleased dependency beyond "Depends on", migrations only add, backfills are safe to run twice (`/docs/developer/releasing`)
- [ ] All user-facing text uses I18n locale keys (no hardcoded strings)
- [ ] Controllers enforce Pundit authorization where the action is policy-scoped
- [ ] RESTful routes only (no custom aliases, no single-action sub-resource controllers)
- [ ] Comments only where code can't say it (gist + pointer; see `/docs/developer/conventions`) — the *why* is in this PR body
- [ ] **Docs:** if you changed behavior, the relevant `app/docs/*` page is updated — and if you touched **auth, onboarding, invitations, or clientside** flows, re-check the Application Flows guide (`app/docs/user/application-flows.md`)

## UI changes only

<!-- Delete this whole section for non-UI PRs. -->

- [ ] Built on a documented `UI::*` primitive / canonical design-system class (no raw hex, off-system fonts, or `focus:ring-*`)
- [ ] Verified in **both** light and dark themes (the axe AAA audit runs locally by default — a local failure is real; see #541/#542)
- [ ] Screenshots attached below (both themes)

<!-- Screenshots: -->
