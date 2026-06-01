# AGENTS.md

> **Status (2026-05-20)**: Repo is mid-refactor from POC to production distribution layer. See [`plan.md`](./plan.md) for the locked decisions (D1–D22), open question status, phase tracker, and Mermaid diagrams. Always read `plan.md` before making structural changes.

Repository: distribution layer for `duynhlab/*-service` repos. Repacks upstream-built Linux binaries into per-service RPMs (and later DEBs) and serves them via a YUM repository on GitHub Pages.

## Current layout (post Phase 0)

```
plan.md                              Roadmap + decisions + diagrams (source of truth)
AGENTS.md                            This file
README.md                            Short repo intro
Makefile                             Local entrypoint (build-local, build, clean)
scripts/                             (Phase 1) build/render/ops scripts
.github/workflows/build.yml          Placeholder lint workflow
docs/                                Phase 3 will replace POC docs
```

POC artifacts removed in Phase 0: `sources/`, `configs/`, `Dockerfile`, `rpm/`, `nfpm.yaml`, `scripts/build*.sh`, `scripts/{pre,post}{install,remove}.sh`. Restore via `git checkout archive/poc-v0`.

## Conventions

- **Source of truth**: `services.yaml` (Phase 1) lists every service with repo / binary / port / db / dependencies. All workflows + scripts render from it.
- **Packaging tool**: nFPM. No `rpmbuild`. No Docker build environment.
- **Binary origin**: GitHub Release tarballs from `duynhlab/<svc>-service`. Local fallback: `scripts/build-local.sh` reads `$DUYNHLAB_SRC_ROOT/<svc>-service` checkout (default: `..`).
- **Layout (FHS)**: `/opt/duynhlab/<svc>/` binary + migrations, `/etc/duynhlab/<svc>/` config + env, `/usr/lib/systemd/system/duynhlab-<svc>.service` (per-service, not template).
- **User**: `duynhlab:duynhlab`, system account, `nologin`, home `/opt/duynhlab`.
- **DB**: PostgreSQL ≥14, dedicated DB+user per service (`duynhlab_<svc>`, `duynhlab_<svc>_app`, `duynhlab_<svc>_migrator`). Migrations via `golang-migrate` shipped in `duynhlab-common`. Not auto-run.
- **Credentials**: Password generated at postinstall (random 32-char), written to `/etc/duynhlab/<svc>/<svc>.env` (0640 root:duynhlab). Never overwritten on reinstall.
- **Logs**: journald only.
- **Ops CLI**: `duynhlab-ctl {list,start,stop,restart,status,enable,disable,logs,health,version,config,ports}` shipped in `duynhlab-common`.

## Phase tracker

See `plan.md` § Phase 0–5 checklists. Mark `[x]` per task as PRs land.

## Don'ts

- Don't reintroduce `sources/` POC pattern. Service code lives in its own repo.
- Don't bundle PostgreSQL server. Only `Requires: postgresql`.
- Don't mutate user-owned config (`/etc/redis/redis.conf`, `/etc/nginx/nginx.conf`). Drop fragments under `conf.d/`.
- Don't auto-run DB migrations in postinstall.
- Don't enable/start units in postinstall.
- Don't ship default passwords or `__CHANGEME__` placeholders — gen real random.
