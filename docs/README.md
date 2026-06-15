# duynhlab/packages documentation

Distribution layer that repacks the upstream `duynhlab/*-service` binaries into a
single **mega-RPM** and serves it from a YUM repository on GitHub Pages.

Start with the repo [`README.md`](../README.md) for the high-level overview.
The docs are numbered as a reading order — **understand → install → operate →
build → release → extend** — but each guide stands alone, so jump straight to
the one that matches your task.

## Index

| # | Document | Audience | Contents |
|---|---|---|---|
| 001 | [`001-architecture.md`](001-architecture.md) | Anyone | Why a mega-RPM, component map, services table, FHS layout, systemd model, install/upgrade/remove lifecycle diagrams, database model |
| 002 | [`002-install.md`](002-install.md) | Operators installing the RPM | Add the repo, install, bootstrap the database, start, upgrade, downgrade, remove, troubleshooting |
| 003 | [`003-operations.md`](003-operations.md) | Operators (day-2) | `duynhctl` and `duynhdb` reference, bring-up flow, systemd targets, configuration files, upgrade, remove, troubleshooting |
| 004 | [`004-build.md`](004-build.md) | Contributors / release engineers | Build pipeline, scripts, runner auto-detection, Makefile targets, CI workflows, gh-pages publishing, versioning |
| 005 | [`005-release.md`](005-release.md) | Release engineers | Runbook: cut a release, same-day hotfix, re-publish a tag, rollback/downgrade, audit composition, troubleshooting per job |
| 006 | [`006-add-service.md`](006-add-service.md) | Contributors | Onboard a new service: repo prerequisites, registry entry, the full hardcoded touch-point checklist, verify, ship |
| 007 | [`007-file-reference.md`](007-file-reference.md) | Anyone (lookup) | Every installed file in one place: binaries, CLI tools, configs, units, runtime state — path, owner/mode, what creates it, what survives upgrades |

## Conventions used in these docs

- Diagrams are [Mermaid](https://mermaid.js.org/) and render natively on GitHub.
- Service set: `auth user product cart order review notification shipping` (8
  backends) plus the static `frontend`.
- `duynhdb` is **per-service** — every invocation takes one service
  name (e.g. `duynhdb migrate auth`).
- Paths follow the FHS split: `/opt/duynhlab` (immutable payload) vs
  `/etc/duynhlab` (mutable env/state, preserved across upgrades).
