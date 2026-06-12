# AGENTS.md

Guide for AI agents and contributors working on `duynhlab/packages`.

> **Source of truth:** [`plan-spec.md`](./plan-spec.md) holds the locked decisions (S-D1…S-D17),
> the roadmap status, and the Backlog of undecided items. It is gitignored (internal). **Read it
> before any structural change.** `services.yaml` is the source of truth for the service list.

## Contribution workflow for AI agents

- **Identity:** this repo lives under `~/Working/Me/duynhlab` → personal `duynhne` GitHub identity via
  conditional gitconfig. Before any git op, verify `git config user.email` is the personal email.
- **Commits:** Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `ci:`…). **Do NOT add a
  `Co-Authored-By: Claude …` trailer** — commits are duynhne-only.
- **Branching:** never commit on `main`; branch first (`feat/…`, `fix/…`, `docs/…`) and open a PR.
- **Pre-PR checks:**
  - `bash -n` every script you touched (and `shellcheck` if installed).
  - `make build` must produce a clean RPM; run `make test-install` (and `make test-integration` when changing
    runtime/migration/systemd behavior).
  - Keep changes surgical — every changed line should trace to the task (see `CLAUDE.md`).
- **Scope:** service *code* lives in the `duynhlab/<svc>-service` repos, not here. This repo only
  repackages built artifacts.

## Code quality

Security/reliability invariants — do not regress these:

- **No default passwords.** A random 32-char password is generated per service at first install and
  written to `/etc/duynhlab/<svc>.env` (`0640 root:duynhlab`). Never ship `__CHANGEME__`. Never
  overwrite an existing env file on reinstall/upgrade.
- **Postinstall never mutates external state:** no DB migrations, no `systemctl enable`/`start`. RPM
  scriptlets must be idempotent.
- **Never mutate operator-owned config** (`/etc/nginx/nginx.conf`, `/etc/valkey/valkey.conf`). Drop
  fragments under `conf.d/` only.
- **Migrations are forward-only** and run as the migrator role against the **direct** DB host — never
  through a pooler (DDL via PgBouncer/PgCat is unsafe).
- **Logs go to journald only** — no `/var/log/...` files from services.
- Systemd units keep the hardened sandbox already in the template (`ProtectSystem=strict`,
  `NoNewPrivileges`, `MemoryDenyWriteExecute`, restricted syscalls/address families).

## Project overview

`duynhlab/packages` is the **distribution layer** for the duynhlab e-commerce platform. It repacks
upstream-built Linux binaries from the `duynhlab/*-service` repos into **one mega-RPM**
(`duynhlab-<VERSION>-1.el9.x86_64.rpm`) and serves it via a YUM repository on GitHub Pages. It ships 8
Go backend services + 1 frontend SPA + operational tooling. Scope v1: RPM only, EL9 (Rocky/Alma 9),
amd64.

## Repository layout

```
services.yaml                  Single source of truth: every service (repo/binary/port/grpc_port/db/deps)
Makefile                       Local entrypoint (fetch-sources, build-local, stage, build, test-install, …)
scripts/                       Build / render / ops scripts
├── lib/common.sh              Shared bash helpers (yq accessors: svc_field, svc_build_env, logging)
├── fetch-sources.sh           git clone/pull each service repo
├── build-local.sh             Build one service (go build / npm build) → build/<svc>/raw/
├── render-systemd.sh          services.yaml → per-service .service + duynhlab-platform.target
├── stage-all.sh               Assemble FHS payload → Source0 staging tarball
├── build-rpm.sh               rpmbuild packages/rpm/duynhlab.spec → dist/*.rpm (host/podman/docker)
├── publish-yum-repo.sh        createrepo_c → gh-pages YUM metadata
└── test-install.sh / test-integration.sh   install / integration tests
packages/
├── common/scripts/            duynhctl, duynhdb, duynhenv, duynhpass
└── rpm/
    ├── duynhlab.spec          The mega-RPM SPEC (rpmbuild) — lives with the assets it packages
    ├── systemd/               duynhlab-service.tmpl.service, *.target(.tmpl)
    ├── scriptlets/            %pre/%post/%postun fragments
    ├── secret-tpl/            <svc>.env.tpl (PORT/GRPC_PORT/DB_*; __DB_PASSWORD__ placeholder)
    ├── nginx/ valkey/ postgresql/ logrotate/   config templates
    └── lib/                   init-service.sh, password-generator.sh
docs/                          numbered reading order: 001-architecture … 006-add-service (see docs/README.md)
.github/workflows/             _build-test.yml (reusable pipeline), build.yml (validate — calls it),
                               release.yml (tag-driven publish — calls it too)
build/  dist/                  Generated, gitignored — never hand-edit
plan-spec.md                   Internal roadmap + decisions + backlog (gitignored)
```

## Packaging architecture

**One mega-RPM**, built with `rpmbuild` against `packages/rpm/duynhlab.spec` — **not** per-service nFPM
(nFPM was abandoned, D27; `nfpm*.yaml`/`render-nfpm.sh` do not exist). Rationale: the platform deploys
as a unit, so atomic upgrades + one dependency closure + one `dnf install duynhlab` win over
independent per-service versioning.

- Payload lands under `/opt/duynhlab/` (immutable, replaced each upgrade).
- CLI tooling ships to `/opt/duynhlab/lib/` with `/usr/bin/` symlinks:
  `duynhctl` (service ops), `duynhdb` (DB bootstrap/migrate/status),
  `duynhenv`, `duynhpass`.
- systemd: each `duynhlab-<svc>.service` is `PartOf=duynhlab-platform.target` and ordered
  `After=duynhlab-infra.target` (which `Wants=` external `nginx`/`postgresql`/`valkey`).
- Each unit loads env in order: `env-global.properties` → `<svc>.env` (required) → `<svc>.override`.

## Build pipeline

Three stages, all driven by `services.yaml`:

1. **`build-local.sh <svc>`** — `cd $DUYNHLAB_SRC_ROOT/<src_dir>`, `go build` (backend,
   `CGO_ENABLED=0 GOOS=linux GOARCH=amd64`) or `npm ci && npm run build` (frontend, with `build.env`
   such as `VITE_API_BASE_URL` baked in). Output: `build/<svc>/raw/<binary>-<ver>-linux-amd64.tar.gz`
   + `build-info.env` (carries `SCHEMA_VERSION` = highest embedded migration, audit-only).
2. **`stage-all.sh`** — extract every backend tarball + frontend dist into
   `build/staging/opt/duynhlab/`, write `BINARY_VERSION`/`SCHEMA_VERSION`, copy CLI tools + config
   templates, generate the **composition manifest** (`etc/manifest` — the 9 service SHAs, used by
   release notes and shipped in the RPM), run `render-systemd.sh`, then tar everything as the
   Source0 staging tarball.
3. **`build-rpm.sh`** — `rpmbuild -ba packages/rpm/duynhlab.spec` (host, else podman/rockylinux:9, else
   docker) → `dist/duynhlab-<VERSION>-1.el9.x86_64.rpm`.

## Build, test, lint

```bash
make help                       # list targets + resolved env
make fetch-sources [REF=main]   # clone/update all service repos under $DUYNHLAB_SRC_ROOT
make build-local SERVICE=auth   # build one service
make build-local-all            # build every service in services.yaml
make render-systemd             # render units only
make stage                      # assemble Source0 staging tarball
make build                      # stage + rpmbuild -> dist/
make test-install               # file-level install check (Rocky 9 container)
make test-integration           # full systemd boot + health (podman + Postgres sidecar)
make publish-repo               # stage gh-pages YUM tree
make release                    # cut a release: next CalVer tag -> push -> release.yml publishes
make clean                      # rm build/ dist/
```

Env knobs: `VERSION` (CalVer default), `DUYNHLAB_SRC_ROOT` (default `..`),
`BUILD_RUNNER` (`host|podman|docker`), `APP_IMAGE` (test-integration systemd image).
Lint = `bash -n` on every script (+ `shellcheck` when available). No Go toolchain build here — binaries
come pre-built from the service repos.

## Generated / gitignored files

`build/` and `dist/` are **generated and gitignored — never hand-edit and never commit**:

- `build/<svc>/raw/` — per-service tarballs + `build-info.env`
- `build/staging/` — the assembled FHS tree
- `build/systemd/` — rendered `.service`/`.target` files (regenerate via `render-systemd.sh`)
- `build/sources/duynhlab-<ver>-staging.tar.gz` — the SPEC's `Source0`
- `dist/*.rpm` — output packages

`plan-spec.md` stays gitignored (internal). `AGENTS.md` (this file) is tracked.

## Conventions

- **FHS layout:** binaries `/opt/duynhlab/<svc>/bin/`, env **flat** at `/etc/duynhlab/<svc>.env`
  (not `/etc/duynhlab/<svc>/<svc>.env`), units `/usr/lib/systemd/system/duynhlab-<svc>.service`
  (per-service, rendered from `duynhlab-service.tmpl.service`).
- **Service user:** `duynhlab:duynhlab`, system account, `nologin`, home `/opt/duynhlab`.
- **Database:** PostgreSQL ≥14, one DB + two roles per service: `duynhlab_<svc>` (db),
  `duynhlab_<svc>_app` (runtime CRUD), `duynhlab_<svc>_migrator` (DDL).
- **Migrations:** embedded in each service binary (`//go:embed`, golang-migrate v4 via
  `duynhlab/pkg/migratex`, forward-only `000NNN_*.up.sql`). Run by the binary itself:
  `duynhdb <svc> migrate` execs `/opt/duynhlab/<svc>/bin/<binary> migrate`. This repo ships
  **no** loose SQL and **no** separate migrate tool (D23/D24).
- **Env vars:** `DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_SSLMODE DB_POOL_*`, plus `PORT` and (for
  gRPC services) `GRPC_PORT`. No `DATABASE_URL`. `secret-tpl/<svc>.env.tpl` uses the `__DB_PASSWORD__`
  placeholder, substituted at install.
- **Ops CLI:** `duynhctl {list,start,stop,restart,status,enable,disable,logs,health,version,config,ports}`;
  `duynhdb <svc> {bootstrap,migrate,status}` (`bootstrap` needs `SUPERUSER_DSN`).

## Testing

- **`test-install.sh`** — installs the RPM in a `rockylinux:9` container, asserts the FHS layout and
  that **no `migrations/` dir** and **no `duynhlab-db-migrate`** are shipped.
- **`test-integration.sh`** — podman pod with a Postgres 16 sidecar + a systemd app container; installs the
  RPM, runs `bootstrap`+`migrate`+`status` per backend, `enable --now duynhlab-platform.target`, then
  `curl /health` for each service. Uses `ENV=production`.
  - **`APP_IMAGE` must contain `/sbin/init`.** The default `centos:stream9` is minimal (no systemd) —
    build one first:
    ```
    podman build -t localhost/duynhlab-test-init - <<'D'
    FROM quay.io/centos/centos:stream9
    RUN dnf -y install systemd && dnf clean all
    D
    APP_IMAGE=localhost/duynhlab-test-init make test-integration
    ```

## Gotchas and non-obvious rules

- **Merging to `main` does NOT publish anything.** Releases are tag-driven: `make release` creates the
  next free annotated CalVer tag (`vYYYY.MM.DD[.N]`) and `release.yml` builds + tests + publishes that
  exact RPM in one run (version = tag). Don't recreate a `workflow_run` auto-publish chain, and don't
  hand-craft release tags — use `make release` (S-D18).
- **Migrations live in the binary**, not in the RPM. Don't reintroduce a `duynhlab-db-migrate` binary,
  loose `.sql`, or Flyway→golang-migrate filename conversion (D23/D24).
- **Mega-RPM, not nFPM** (D27). `nfpm` is referenced nowhere; any `build/*/nfpm.yaml` are dead.
- **`plan-spec.md` is the gitignored source of truth** — read it before structural changes.
- **Every service defaults to HTTP `8080` and gRPC `9090` in code.** On a shared host they collide, so
  `PORT`/`GRPC_PORT` MUST be set per service from `services.yaml` (`port`, `grpc_port`).
- **Env path is flat:** `/etc/duynhlab/<svc>.env`.
- **`duynhctl`'s `yq` comes via `Requires: yq >= 4`** (EPEL ships mikefarah yq ≥4.47 on EL9 —
  historically it was the unrelated python-yq, so re-verify if the floor ever changes). Don't bundle
  a private copy; the ctl resolver prefers `/opt/duynhlab/lib/yq` only as an escape hatch (B6).
  **Build machines need mikefarah yq too** (`yq_bin()` in `scripts/lib/common.sh` parses
  `services.yaml` during builds) — the spec's `Requires:` does NOT cover them; CI installs it in
  `_build-test.yml`, devs install it once. Don't delete `yq_bin()` thinking the spec replaced it.
- **Frontend `VITE_API_BASE_URL` is baked at build time** — changing the gateway origin requires a
  rebuild.
- **Never co-locate two services in one database** — golang-migrate's unqualified `schema_migrations`
  table would collide. Keep `duynhlab_<svc>` isolated (D25). Prod uses shared *clusters* but separate
  *databases*, which is safe.
- **Don't bundle a PostgreSQL server** — only `Requires: postgresql` (client).
- Restore the removed POC tree via `git checkout archive/poc-v0`.
