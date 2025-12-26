# Changelog

All notable changes to the Platform package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2025-12-26

### Added
- **Multi-format package support**: Generate RPM and DEB packages from single `nfpm.yaml` configuration
- **nFPM integration**: Replaced rpmbuild with nFPM for modern, multi-format packaging
- **Standardized directory structure**:
  - Renamed `repo/` to `sources/` for clarity
  - Reorganized `apps/` into `configs/apps/` with `common/` subdirectory
  - Moved `infra/` to `configs/infra/` to consolidate all configs
  - Added `build/platform/` staging area for package preparation
- **New build script**: `scripts/build-nfpm.sh` for nFPM package generation
- **Refactored installation scripts**: Extracted and improved maintainability
  - `scripts/preinstall.sh` - Port checks, log directories, user/group setup
  - `scripts/postinstall.sh` - Service setup, Redis/Nginx config, service startup
  - `scripts/preremove.sh` - Service stop and disable
  - `scripts/postremove.sh` - Systemd daemon reload
- **Format-specific paths**: Automatic handling of RPM vs DEB systemd paths
  - RPM: `/usr/lib/systemd/system/`
  - DEB: `/lib/systemd/system/`
- **New Makefile targets**:
  - `make validate` - Validate nfpm.yaml configuration
  - `make build` - Build RPM + DEB packages (default)
  - `make build-rpm` - Build RPM package only
  - `make build-deb` - Build DEB package only
- **Comprehensive documentation**:
  - Installation scripts lifecycle documentation
  - Build platform explanation
  - Scripts types explanation
  - Updated getting started guide

### Changed
- **Build system**: Migrated from rpmbuild to nFPM
- **Package configuration**: Single `nfpm.yaml` at project root replaces RPM spec
- **Build process**: Unified staging area (`build/platform/`) for all formats
- **Output format**: Text labels (`[INFO]`, `[SUCCESS]`, `[ERROR]`, `[WARNING]`) replace icons in all scripts
- **Makefile**: Reorganized targets, removed duplicates, improved help output
- **CI/CD**: Updated GitHub Actions workflow to use nFPM

### Removed
- **APK package format**: Removed Alpine Linux (APK) support
- **build-all target**: Removed redundant target (covered by default `build`)

### Deprecated
- **Legacy build**: `make build-legacy` still available but deprecated
- **RPM spec**: `rpm/specs/platform.spec` backed up as `rpm/specs/platform.spec.backup`

### Migration Notes
- Old `make build` now uses nFPM (RPM + DEB)
- Legacy rpmbuild available via `make build-legacy`
- Directory structure changes require updating any custom scripts
- Installation scripts now use text labels instead of icons

## [1.0.1] - 2025-12-24

### Added
- Initial platform RPM package structure
- Support for multiple Go services (api-server, user-api, checkout-api, voter-api)
- Systemd target-based orchestration
- Nginx reverse proxy integration
- Redis caching layer support
- Initialization scripts (print-version.sh)
- GitHub Actions CI/CD workflow with dynamic versioning

### Changed
- Renamed from "micro-platform" to "platform"
- Renamed "conf-shared" to "conf"
- Upgraded Go version from 1.21 to 1.25

## [1.0.0] - 2025-12-23

### Added
- Initial release of Platform
- Unified RPM package with all services bundled together
- Systemd target orchestration (platform-all.target, platform-infra.target)
- Nginx reverse proxy configuration
- Redis configuration integration
- Version logging script (print-version.sh)
- Port availability checks during installation
- Automatic service startup after installation
- Log directory creation and permissions setup

### Services Included
- api-server (port 8079)
- user-api (port 8080)
- checkout-api (port 8081)
- voter-api (port 8082)
- nginx (port 80)
- redis (port 6379)

### Infrastructure
- Systemd service files for all services
- Nginx configuration for reverse proxy
- Redis configuration snippet
- Shared and service-specific configuration files

---

## Version Mapping

This table maps CHANGELOG versions to package versions and releases (RPM/DEB).

| CHANGELOG Version | Package Version | Package Release | Date | Status |
|-------------------|-----------------|-----------------|------|--------|
| 2.0.0 | 2.0.0 | 1 | 2025-12-26 | Released |
| 1.0.1 | 1.0.1 | 1 | 2025-12-24 | Released |
| 1.0.0 | 1.0.0 | 1 | 2025-12-23 | Released |

### Version Format

- **CHANGELOG Version**: Semantic version (MAJOR.MINOR.PATCH)
- **Package Version**: Same as CHANGELOG version (defined in `nfpm.yaml`)
- **Package Release**: Package release number (incremented for rebuilds of same version)
  - First release: `1`
  - Rebuild same version: `2`, `3`, etc.
  - New version: Reset to `1`

### Example Version Progression

| Scenario | CHANGELOG | Package Version | Package Release |
|----------|-----------|-----------------|-----------------|
| Initial release | 1.0.0 | 1.0.0 | 1 |
| Bug fix rebuild | 1.0.0 | 1.0.0 | 2 |
| New feature | 1.1.0 | 1.1.0 | 1 |
| Bug fix rebuild | 1.1.0 | 1.1.0 | 2 |
| Breaking change | 2.0.0 | 2.0.0 | 1 |

## How to Update

When releasing a new version:

1. Update `CHANGELOG.md` with new version section
2. Update `nfpm.yaml`:
   - Update `version:` field
   - Update `release:` field (increment for same version rebuilds)
3. Commit changes with message: `chore: bump version to X.Y.Z`

### Legacy RPM Spec (if using build-legacy)

If updating the legacy RPM spec (`rpm/specs/platform.spec`):
- Update `Version:` field
- Update `Release:` field
- Add entry to `%changelog` section with format:
  ```
  * Day Mon DD YYYY Name <email> - version-release
  - Change description line 1
  - Change description line 2
  ```

