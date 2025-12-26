# Platform - Multi-Format Package Builder

A unified service platform packaged as RPM, DEB, and other Linux package formats using nFPM. Build once, deploy everywhere with a single configuration.

## Features

- **Multiple Go Services**: Each service built as a separate binary from source code
- **Multi-Format Packaging**: Generate RPM, DEB, IPK, and Arch Linux packages from a single `nfpm.yaml` configuration
- **Unified Packaging**: Single package contains all services and configurations
- **Systemd Orchestration**: Target-based service management with dependency handling
- **Format-Specific Paths**: Automatically handles RPM vs DEB systemd path differences
- **Nginx Integration**: Built-in reverse proxy configuration
- **Redis Support**: Integrated caching layer
- **Standardized Structure**: Clear directory organization (sources/, configs/, build/)
- **Go 1.25**: Modern Go tooling and performance improvements

## Quick Start

```bash
# Install nFPM (if not already installed)
go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.44.1
export PATH=$PATH:$(go env GOPATH)/bin

# Build packages (RPM + DEB)
make build

# Or build specific format
make build-rpm   # RPM only
make build-deb   # DEB only
make build-all   # All formats (RPM, DEB)

# Install on target system
# For RPM (RHEL/Rocky Linux):
sudo dnf install dist/platform-*.rpm

# For DEB (Debian/Ubuntu):
sudo dpkg -i dist/platform-*.deb

# Start all services
sudo systemctl start platform-all.target
```

## Documentation

- **[Getting Started](docs/getting-started.md)** - Step-by-step guide for newcomers
- **[Build Process](docs/build-process.md)** - Detailed build flow documentation
- **[Directory Structure](docs/directory-structure.md)** - Project organization and file structure

## Project Structure

```
rpm-builder/
├── sources/              # Go service source code (from multiple repositories)
│   ├── api-server/
│   ├── user-api/
│   └── ...
├── configs/              # All configuration files
│   ├── apps/            # Application configs
│   │   ├── common/      # Shared configs
│   │   └── {service}/   # Service-specific configs
│   └── infra/           # Infrastructure configs (nginx, redis)
├── build/               # Build staging area (generated)
│   └── platform/        # Files staged for packaging
├── nfpm.yaml           # nFPM configuration (multi-format)
├── scripts/             # Build scripts
│   ├── build.sh        # Legacy RPM build (rpmbuild)
│   ├── build-nfpm.sh   # nFPM build script
│   ├── preinstall.sh   # Pre-installation script
│   ├── postinstall.sh  # Post-installation script
│   ├── preremove.sh    # Pre-removal script
│   └── postremove.sh   # Post-removal script
├── rpm/
│   ├── specs/          # RPM specification (legacy - only used for make build-legacy)
│   │   └── platform.spec  # NOT used by nFPM (nFPM uses nfpm.yaml instead)
│   ├── files/systemd/  # Systemd service files
│   └── platform/lib/  # Initialization scripts
└── dist/               # Output packages (generated)
```

## Requirements

- **Go 1.25+** - Required for building service binaries and nFPM
- **nFPM v2.44.1** - Package builder (install with `go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.44.1`)
- **Make** - For running build commands
- **Docker** (optional) - Only needed for legacy `make build-legacy` command

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Build packages with nFPM (RPM + DEB) [DEFAULT] |
| `make build-rpm` | Build RPM package only |
| `make build-deb` | Build DEB package only |
| `make build-all` | Build all formats (RPM, DEB) |
| `make build-nfpm` | Build packages with nFPM (RPM + DEB) |
| `make build-legacy` | Build RPM using legacy rpmbuild (requires Docker) |
| `make validate-nfpm` | Validate nfpm.yaml configuration |
| `make docker-build` | Build Docker image (for legacy builds) |
| `make clean` | Remove all build artifacts |

## Package Formats

This project generates packages for multiple Linux distributions:

- **RPM** - For RHEL, Rocky Linux, CentOS, Fedora
- **DEB** - For Debian, Ubuntu
- **IPK** - For OpenWrt
- **Arch Linux** - For Arch-based distributions

All formats are generated from a single `nfpm.yaml` configuration file.

## Installation Scripts

The package includes refactored installation scripts:

- **preinstall.sh** - Port availability checks, log directory creation
- **postinstall.sh** - Service setup, Redis/Nginx configuration, service startup
- **preremove.sh** - Service stop and disable
- **postremove.sh** - Systemd daemon reload

All scripts are modular, maintainable, and include better error handling.

## CI/CD

The GitHub Actions workflow (`.github/workflows/build-rpm.yml`) automatically:
- Builds binaries from source
- Generates RPM and DEB packages using nFPM
- Uploads artifacts for download

## Migration from Legacy Build

If you were using the old `rpmbuild` workflow:
- **Legacy build still available**: `make build-legacy` (uses `rpm/specs/platform.spec`)
- **New default**: `make build` uses nFPM (uses `nfpm.yaml`, NOT `platform.spec`)
- **Important**: `rpm/specs/platform.spec` is ONLY used for legacy builds, not for nFPM
- Old RPM spec backed up: `rpm/specs/platform.spec.backup`

## License

MIT
