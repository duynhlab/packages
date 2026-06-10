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
upgrade, remove): [`docs/install.md`](docs/install.md).

### Build locally (maintainer)

```bash
make fetch-sources          # clone every service repo into ../
make build-local-all        # compile binaries + frontend dist
make build                  # stage Source0 tarball + rpmbuild -> dist/*.rpm
make smoke                  # file-level install check in Rocky 9
```

`BUILD_RUNNER=host|podman|docker` is auto-detected. Full pipeline, scripts, and
Makefile reference: [`docs/build.md`](docs/build.md).

## CI in one paragraph

`build-rpms` ([`build.yml`](.github/workflows/build.yml)) validates every PR and
push to `main` (docs-only changes are skipped): job `build` compiles everything,
builds the mega-RPM and smoke-installs it; job `smoke-full` (main + manual) boots
the RPM under real systemd with a Postgres sidecar. Only when `build-rpms` is
green on `main` does `publish-yum-repo`
([`publish-yum-repo.yml`](.github/workflows/publish-yum-repo.yml)) upload the RPM
to a GitHub Release and deploy the YUM metadata to Pages. Details + rationale:
[`docs/build.md`](docs/build.md) § CI workflows.

## Documentation

| Doc | Contents |
|---|---|
| [`docs/install.md`](docs/install.md) | End-user install, bootstrap, upgrade, remove, troubleshooting |
| [`docs/architecture.md`](docs/architecture.md) | What ships in the package, FHS layout, systemd model, lifecycle |
| [`docs/build.md`](docs/build.md) | Build pipeline, scripts, Makefile, CI workflows, publishing |
| [`docs/operations.md`](docs/operations.md) | `duynhlab-ctl`, `duynhlab-db-setup`, systemd targets, day-2 ops |
| [`AGENTS.md`](AGENTS.md) | Repository layout, conventions, contributor/agent guide |
