# Changelog entries

Each pull request adds its changelog entry here as a file of its own, such as
`changelog.d/fix-login.md`. Two PRs never edit the same lines, so their
entries can't conflict.

Write one line saying what changed for someone using the app, under a heading
if one fits:

```markdown
### Fixed

- Signing in no longer loops after a password reset.
```

An entry without a heading goes under "Changed". `bin/release prepare` gathers
every file here into the release's section of `CHANGELOG.md` and deletes
them; this README stays.

A fix for the release under review is the exception: its line goes under that
release's `## v<name>` section in `CHANGELOG.md`, since a file here would wait
for the next release.

The full flow is in `/docs/developer/releasing`.
