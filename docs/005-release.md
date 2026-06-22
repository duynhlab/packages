# Release Runbook

Operational guide for cutting, re-publishing, rolling back, and auditing
releases. Pipeline internals (scripts, workflows, hosting rationale):
[`004-build.md`](004-build.md) § 5.

## 1. Flow at a glance

```
merge to main ──► build-rpms (validate only — never publishes)

make release  ──► annotated tag vYYYY.MM.DD[.N]
                      │ push
                      ▼
              release.yml:  guard ─► build-test (VERSION = tag) ─► publish ─► deploy
                                     └ the RPM that passes the tests is the
                                       byte-identical RPM that gets published
```

Key invariants:

- **Merging to `main` never publishes.** Only a tag does.
- **Published == tested** — build, test, and publish happen in one run on one artifact.
- The RPM's `Version:` always equals the tag (`v2026.06.11` → `duynhlab-2026.06.11-1.el9`).

## 2. Cut a release

```bash
git checkout main && git pull
make release
```

`make release` refuses to run unless you are on a **clean, up-to-date `main`**.
It computes the next free CalVer tag for today, creates an **annotated** tag,
and pushes it — `release.yml` does everything else. Follow along:

```bash
gh run watch "$(gh run list --workflow=release --limit 1 --json databaseId --jq '.[0].databaseId')"
```

When the run is green: the Release page has the RPM + `MANIFEST.txt`, and
`https://duynhlab.github.io/packages` serves metadata indexing the last 3
releases.

## 3. Same-day hotfix

Just run `make release` again — it sees `v2026.06.11` exists and cuts
`v2026.06.11.1` (then `.2`, …). RPM version ordering handles the suffix
correctly, so `dnf upgrade` moves customers forward as expected.

## 4. Re-publish an existing tag

When `publish` or `deploy` fails mid-run (Release exists but Pages metadata is
stale, or vice versa), **do not** delete/re-push the tag. Re-publish it:

```bash
gh workflow run release -f tag=v2026.06.11
```

This is idempotent: it rebuilds + retests from the tag, refreshes the Release
assets (`--clobber`) and notes, regenerates the repodata, and redeploys Pages.

Real examples: the first ever cut needed this twice — PR #36 (createrepo ran
under rootless podman and the scratch cleanup failed) and PR #37 (the deploy
job was missing `id-token: write`). Both times the fix landed on `main` and a
re-publish completed the release without touching the tag.

> A plain tag push onto an existing release is **rejected by `guard`** — silent
> overwrites are exactly what this design removes.

## 5. Rollback / downgrade

The YUM metadata indexes the **last 3 releases**:

```bash
dnf list duynhlab --showduplicates       # what's available
sudo dnf downgrade -y duynhlab           # one step back
sudo dnf install -y duynhlab-2026.06.09  # pin an exact version
```

Older than that: download from the
[Releases page](https://github.com/duynhlab/packages/releases) and
`dnf install ./duynhlab-<ver>-1.el9.x86_64.rpm`.

> ⚠️ Migrations are **forward-only** — downgrading the package does not
> downgrade the schema. Only downgrade across versions with the same
> `SCHEMA_VERSION` (check the release notes / manifest), or restore the DB from
> a pre-upgrade backup. See [`002-install.md`](002-install.md) § Downgrade.

## 6. Audit a release

Every release records its exact composition — the commit of each of the 9
service repos it was built from — in three places that must agree:

| Where | What |
|---|---|
| Release notes | "Composition" table |
| `MANIFEST.txt` release asset | machine-readable copy |
| `/opt/duynhlab/etc/manifest` on an installed host | the same file, shipped in the RPM |

To verify what a customer is actually running:

```bash
cat /opt/duynhlab/etc/manifest          # on the host
gh release download v2026.06.11 --pattern MANIFEST.txt -O - | diff - /opt/duynhlab/etc/manifest
```

## 7. Troubleshooting by job

| Job | Symptom | Cause / action |
|---|---|---|
| `guard` | "not vYYYY.MM.DD[.N]" | Tag was hand-crafted with the wrong format — use `make release` |
| `guard` | "not an ancestor of main" | Tag points at unmerged code — merge first, re-tag |
| `guard` | "Release already exists" | You re-pushed an existing tag — use the re-publish dispatch (§4) |
| `build-test` | install test red | Read the `test-install` step log; reproduce locally with `make test-install` |
| `publish` / `deploy` | failed after Release was created | Fix the cause on `main`, then re-publish the tag (§4) — never delete the tag |

## 8. Where things live

| Artifact | Location |
|---|---|
| RPM + `MANIFEST.txt` | GitHub Release asset (`releases/download/v<tag>/…`) |
| YUM metadata (`repodata/`, `duynhlab.repo`) | `gh-pages` branch → GitHub Pages (KB-sized, orphan, force-pushed per publish) |
| CI artifacts (unreleased builds) | Actions artifacts, 14-day retention — never customer-visible |
