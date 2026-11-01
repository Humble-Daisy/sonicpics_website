<!-- A release/<name> branch into main. The guide: /docs/developer/releasing -->

## Release

- Branch: `release/YYYY.MM.DD`
- Commit reviewed on staging: <!-- the full SHA from the staging deployment record -->

## What ships

<!-- bin/release cut fills this with the release's CHANGELOG.md section. -->

## Held back

<!-- PRs reverted on this branch, each with its revert commit, so next can restore them after the merge-back. Delete if none. -->

## Ship it

The merge button doesn't check what was reviewed. This does: it finds this PR and the commit staging last deployed, asks before shipping, refuses if the branch moved since, then publishes the release and merges `main` back into `next`:

```bash
bin/release ship
```
