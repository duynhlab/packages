# duynhlab/packages documentation

Distribution layer that repacks the upstream `duynhlab/*-service` binaries into a
single **mega-RPM** and serves it from a YUM repository on GitHub Pages.

Start with the repo [`README.md`](../README.md) for the high-level overview, then
pick the guide that matches your task.

## Index

| Document | Audience | Contents |
|---|---|---|
| [`install.md`](install.md) | Operators installing the RPM | Add the repo, install, bootstrap the database, start, upgrade, remove, troubleshooting |
| [`architecture.md`](architecture.md) | Anyone | Why a mega-RPM, component map, services table, FHS layout, systemd model, install/upgrade/remove lifecycle diagrams, database model |
| [`build.md`](build.md) | Contributors / release engineers | Build pipeline, scripts, runner auto-detection, Makefile targets, CI workflows, gh-pages publishing, versioning, adding a service |
| [`operations.md`](operations.md) | Operators (day-2) | `duynhlab-ctl` and `duynhlab-db-setup` reference, bring-up flow, systemd targets, configuration files, upgrade, remove, troubleshooting |

## Conventions used in these docs

- Diagrams are [Mermaid](https://mermaid.js.org/) and render natively on GitHub.
- Service set: `auth user product cart order review notification shipping` (8
  backends) plus the static `frontend`.
- `duynhlab-db-setup` is **per-service** — every invocation takes one service
  name (e.g. `duynhlab-db-setup migrate auth`).
- Paths follow the FHS split: `/opt/duynhlab` (immutable payload) vs
  `/etc/duynhlab` (mutable env/state, preserved across upgrades).
