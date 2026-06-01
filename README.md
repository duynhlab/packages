# duynhlab/packages

> **Status**: Refactor in progress (Phase 0 complete, Phase 1 in progress).
> See [`plan.md`](./plan.md) for the full roadmap and [`AGENTS.md`](./AGENTS.md) for repo conventions.

Distribution layer for the duynhlab platform: repacks per-service Go binaries from upstream service repos into RPMs (and later DEBs), serves them via a YUM repository on GitHub Pages.

## Scope (v1)

- **Format**: RPM only (DEB → Phase 4)
- **Target**: EL9 (Rocky/AlmaLinux 9), amd64
- **Services**: 8 backend (`auth`, `user`, `product`, `cart`, `order`, `review`, `notification`, `shipping`) + 1 frontend
- **Source of binaries**: GitHub Release tarballs of each `duynhlab/<svc>-service` repo

## Layout

```
packages/
├── plan.md                  Refactor tracking document
├── AGENTS.md                Repo conventions for agents/humans
├── services.yaml            (Phase 1) Single source of truth for service list
├── packaging/rpm/           (Phase 1) nFPM templates + systemd units
├── scripts/                 (Phase 1) build-local.sh, build-rpm.sh, render-*.sh, duynhlab-ctl, duynhlab-db-setup
├── .github/workflows/       (Phase 1-2) create-rpm-service, smoke-test, publish-yum-repo, orchestrator
└── docs/                    (Phase 3) install / release-process / adding-service / troubleshooting
```

POC code (`sources/`, `Dockerfile`, `rpm/specs/`, legacy systemd) has been removed in Phase 0. To inspect history: `git checkout archive/poc-v0`.

## Getting started (after Phase 1)

```bash
# Local-build a service from sibling repo checkout (~/Working/Me/duynhlab/<svc>-service)
make build-local SERVICE=auth

# Then package
make build SERVICE=auth VERSION=0.1.0-rc1
ls dist/    # duynhlab-auth-0.1.0-rc1.el9.x86_64.rpm + duynhlab-common-*.rpm
```

See `plan.md` Phase 1 for the full pilot flow and `docs/install.md` (added in Phase 3) for end-user installation.
