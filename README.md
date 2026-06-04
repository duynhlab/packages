# duynhlab/packages

Distribution layer for the **duynhlab** e-commerce platform. It repacks the
Go binaries and frontend build from the upstream `duynhlab/*-service` repos
into a single **mega-RPM** and publishes it through a YUM repository hosted on
GitHub Pages.

- **Format**: RPM (EL9 / Rocky · AlmaLinux · RHEL 9, `x86_64`)
- **Build tool**: `rpmbuild` against [`specs/duynhlab.spec`](specs/duynhlab.spec) — no nFPM, no Docker build image
- **Output**: `duynhlab-<VERSION>-1.el9.x86_64.rpm` (8 backends + frontend + CLI + config templates)
- **Source of truth**: [`services.yaml`](services.yaml) — every script and workflow renders from it

## What ships in the package

| Component | Path (installed) |
|---|---|
| 8 Go backends (`auth` … `shipping`) | `/opt/duynhlab/<svc>/bin/<svc>-service` |
| Frontend SPA (static) | `/opt/duynhlab/frontend/dist/` |
| CLI tools | `/usr/bin/duynhlab-{ctl,db-setup,db-migrate,gen-env,gen-password}` |
| systemd units + targets | `/usr/lib/systemd/system/duynhlab-*.{service,target}` |
| Config templates (nginx/valkey/postgresql/logrotate) | `/opt/duynhlab/<tool>/` → dropped into `/etc/*` on install |
| Mutable env + secrets | `/etc/duynhlab/<svc>.env` (random password, 0640) |

## Quick start

### Install (end user)

```bash
sudo curl -fsSL -o /etc/yum.repos.d/duynhlab.repo \
  https://duynhlab.github.io/packages/duynhlab.repo
sudo dnf install -y duynhlab

SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \
  sudo -E duynhlab-db-setup bootstrap
sudo duynhlab-db-setup migrate
sudo systemctl enable --now duynhlab-platform.target
```

Full guide: [`docs/install.md`](docs/install.md).

### Build locally (maintainer)

```bash
make fetch-sources          # clone every service repo into ../
make build-local-all        # compile binaries + frontend dist
make build                  # stage Source0 tarball + rpmbuild -> dist/*.rpm
make smoke                  # file-level install check in Rocky 9
make publish-repo           # stage gh-pages YUM tree under build/gh-pages/
```

`BUILD_RUNNER=host|podman|docker` is auto-detected. See
[`docs/build.md`](docs/build.md).

## Pipeline at a glance

```mermaid
flowchart LR
  subgraph upstream["duynhlab/*-service repos"]
    A1[auth-service]
    A2[user-service]
    A3[… 6 more]
    F[frontend]
  end

  upstream -->|fetch-sources.sh<br/>git clone| SRC[(../&lt;svc&gt;)]
  SRC -->|build-local.sh<br/>go build / npm build| RAW[build/&lt;svc&gt;/raw/*.tar.gz]
  RAW -->|stage-all.sh| TAR[(Source0<br/>staging.tar.gz)]
  YML[services.yaml] -->|render-systemd.sh| UNITS[systemd units]
  TAR --> RPMBUILD
  UNITS --> RPMBUILD
  SPEC[specs/duynhlab.spec] --> RPMBUILD{{rpmbuild}}
  RPMBUILD --> RPM[dist/duynhlab-VERSION.rpm]
  RPM -->|publish-yum-repo.sh<br/>createrepo_c| REPO[gh-pages YUM repo]
  REPO -->|dnf install| HOST[Target EL9 host]
```

## Repository layout

```
packages/
├── services.yaml              Single source of truth (services, ports, DBs, deps)
├── specs/duynhlab.spec        The one RPM spec (mega-RPM)
├── scripts/                   Build / stage / publish / smoke pipeline
│   ├── fetch-sources.sh         git clone every service repo
│   ├── build-local.sh           compile one service from sibling checkout
│   ├── render-systemd.sh        render units + target from services.yaml
│   ├── stage-all.sh             assemble Source0 staging tarball
│   ├── build-rpm.sh             rpmbuild (host/podman/docker)
│   ├── publish-yum-repo.sh      createrepo_c -> gh-pages tree
│   ├── smoke-install.sh         file-level install verification
│   └── smoke-full.sh            full systemd smoke (podman + Postgres sidecar)
├── packaging/
│   ├── common/scripts/        CLI tools (duynhlab-ctl, duynhlab-db-setup, …)
│   └── rpm/                    spec assets: scriptlets, systemd tmpl, nginx,
│                              valkey, postgresql, logrotate, secret-tpl, lib
├── .github/workflows/
│   ├── build.yml              build-rpms (PR + push to main)
│   ├── smoke-test-rpm.yml     full systemd smoke (manual / callable)
│   └── publish-yum-repo.yml   build + publish to gh-pages (after build-rpms)
└── docs/                      Documentation (see below)
```

## Documentation

| Doc | Contents |
|---|---|
| [`docs/README.md`](docs/README.md) | Documentation index |
| [`docs/install.md`](docs/install.md) | End-user install, bootstrap, upgrade, remove, troubleshooting |
| [`docs/architecture.md`](docs/architecture.md) | Package layout, components, FHS map, lifecycle diagrams |
| [`docs/build.md`](docs/build.md) | Build pipeline, scripts, Makefile, CI workflows |
| [`docs/operations.md`](docs/operations.md) | `duynhlab-ctl`, `duynhlab-db-setup`, systemd targets, day-2 ops |

## Conventions

- **Binary origin**: GitHub Release tarballs from `duynhlab/<svc>-service`; local fallback `build-local.sh` reads `$DUYNHLAB_SRC_ROOT/<svc>-service` (default `..`).
- **FHS**: `/opt/duynhlab` immutable payload · `/etc/duynhlab` mutable state · journald-only logs.
- **User**: `duynhlab:duynhlab`, system account, `nologin`.
- **DB**: PostgreSQL ≥14, one database + `app`/`migrator` role per service. Migrations are **not** auto-run; units **not** auto-started.
- **Secrets**: random 32-char `DB_PASSWORD` generated at `%post`, preserved on upgrade, never shipped as defaults.
