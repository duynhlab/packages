# Changelog

All notable changes to the Platform RPM package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

This table maps CHANGELOG versions to RPM package versions and releases.

| CHANGELOG Version | RPM Version | RPM Release | Date | Status |
|-------------------|-------------|-------------|------|--------|
| 1.0.0 | 1.0.0 | 1 | 2025-12-23 | Released |

### Version Format

- **CHANGELOG Version**: Semantic version (MAJOR.MINOR.PATCH)
- **RPM Version**: Same as CHANGELOG version (defined in `rpm/specs/platform.spec`)
- **RPM Release**: Package release number (incremented for rebuilds of same version)
  - First release: `1`
  - Rebuild same version: `2`, `3`, etc.
  - New version: Reset to `1`

### Example Version Progression

| Scenario | CHANGELOG | RPM Version | RPM Release |
|----------|-----------|-------------|-------------|
| Initial release | 1.0.0 | 1.0.0 | 1 |
| Bug fix rebuild | 1.0.0 | 1.0.0 | 2 |
| New feature | 1.1.0 | 1.1.0 | 1 |
| Bug fix rebuild | 1.1.0 | 1.1.0 | 2 |
| Breaking change | 2.0.0 | 2.0.0 | 1 |

## How to Update

When releasing a new version:

1. Update `CHANGELOG.md` with new version section
2. Update `rpm/specs/platform.spec`:
   - Update `Version:` field
   - Update `Release:` field (increment for same version rebuilds)
   - Add entry to `%changelog` section with format:
     ```
     * Date Name <email> - version-release
     - Change description
     ```
3. Commit changes with message: `chore: bump version to X.Y.Z`

## RPM Changelog Format

The `%changelog` section in `platform.spec` follows RPM standard format:

```
* Day Mon DD YYYY Name <email> - version-release
- Change description line 1
- Change description line 2
```

Example:
```
* Mon Dec 23 2025 Platform Team <team@example.com> - 1.0.0-1
- Initial release of Platform
- Unified RPM package with all services
- Systemd target orchestration
- Nginx reverse proxy integration
```

