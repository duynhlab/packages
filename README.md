# duynhlab/packages

Distribution layer for the **duynhlab** e-commerce platform. It repacks the
Go binaries and frontend build from the upstream `duynhlab/*-service` repos
into a single **mega-RPM** and publishes it through a YUM repository hosted on
GitHub Pages (metadata) + GitHub Releases (RPM assets).

- **Format**: RPM (EL9 / Rocky · AlmaLinux · RHEL 9, `x86_64`)
- **Build tool**: `rpmbuild` against [`specs/duynhlab.spec`](specs/duynhlab.spec) — no nFPM, no Docker build image
- **Output**: `duynhlab-<VERSION>-1.el9.x86_64.rpm` (8 backends + frontend + CLI + config templates)
- **Source of truth**: [`services.yaml`](services.yaml) — every script and workflow renders from it

## Quick start

### Install (end user)

```bash
sudo curl -fsSL -o /etc/yum.repos.d/duynhlab.repo \
  https://duynhlab.github.io/packages/duynhlab.repo
sudo dnf install -y duynhlab
```

Then bootstrap the per-service databases and start the platform — full steps
(prerequisites, per-service `duynhlab-db-setup bootstrap`/`migrate`, verify,
upgrade, remove): [`docs/002-install.md`](docs/002-install.md).

### Build locally (maintainer)

```bash
make fetch-sources          # clone every service repo into ../
make build-local-all        # compile binaries + frontend dist
make build                  # stage Source0 tarball + rpmbuild -> dist/*.rpm
make test-install           # file-level install check in Rocky 9
```

`BUILD_RUNNER=host|podman|docker` is auto-detected. Full pipeline, scripts, and
Makefile reference: [`docs/004-build.md`](docs/004-build.md).

## CI in one paragraph

`build-rpms` ([`build.yml`](.github/workflows/build.yml)) **validates** every PR
and push to `main` (docs-only changes skipped) — build + install test on every
run, plus the full systemd + Postgres integration test on `main` pushes and
manual dispatches — but never publishes. Both it and `release.yml` share one
pipeline: [`_build-test.yml`](.github/workflows/_build-test.yml). A **release is cut by
pushing a CalVer tag** (`make release` → `v2026.06.11`, second cut of the day
`v2026.06.11.1`): [`release.yml`](.github/workflows/release.yml) builds the RPM
with the tag as its version, runs the same tests on that exact RPM, then uploads
it to a GitHub Release (notes auto-generated + a manifest of the 9 service
commits) and refreshes the YUM metadata on Pages — indexing the **last 3
releases**, so `dnf downgrade duynhlab` works. Details + rationale:
[`docs/004-build.md`](docs/004-build.md) § CI workflows.

## Documentation

| Doc | Contents |
|---|---|
| [`docs/001-architecture.md`](docs/001-architecture.md) | What ships in the package, FHS layout, systemd model, lifecycle |
| [`docs/002-install.md`](docs/002-install.md) | End-user install, bootstrap, upgrade, downgrade, remove, troubleshooting |
| [`docs/003-operations.md`](docs/003-operations.md) | `duynhlab-ctl`, `duynhlab-db-setup`, systemd targets, day-2 ops |
| [`docs/004-build.md`](docs/004-build.md) | Build pipeline, scripts, Makefile, CI workflows, publishing |
| [`docs/005-release.md`](docs/005-release.md) | Release runbook: cut, same-day hotfix, re-publish, rollback, audit |
| [`docs/006-add-service.md`](docs/006-add-service.md) | Onboarding a new service: prerequisites, registry entry, touch-point checklist |
| [`AGENTS.md`](AGENTS.md) | Repository layout, conventions, contributor/agent guide |
