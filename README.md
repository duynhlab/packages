# Platform - RPM Builder

A unified service platform packaged as a single RPM containing multiple Go APIs, Nginx reverse proxy, and systemd orchestration. Build once, deploy everywhere with a single RPM package.

## Features

- **Multiple Go Services**: Each service built as a separate binary from source code
- **Unified Packaging**: Single RPM package contains all services and configurations
- **Systemd Orchestration**: Target-based service management with dependency handling
- **Nginx Integration**: Built-in reverse proxy configuration
- **Redis Support**: Integrated caching layer
- **Docker-based Build**: Clean, reproducible builds using Rocky Linux 9
- **Go 1.25**: Modern Go tooling and performance improvements

## Quick Start

```bash
# Build RPM package
make build

# Install on target system
sudo dnf install dist/platform-*.rpm

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
├── repo/              # Go service source code
├── apps/              # Configuration files
├── infra/             # Infrastructure configs (nginx, redis)
├── rpm/
│   ├── specs/         # RPM specification
│   ├── files/         # Systemd service files
│   └── platform/lib/  # Initialization scripts
├── scripts/           # Build scripts
└── docs/              # Documentation
```

## Requirements

- Go 1.25+
- Docker
- Rocky Linux 9 (or compatible RHEL-based distribution)
- Make

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Build RPM package (includes docker-build) |
| `make docker-build` | Build Docker image for RPM builds |
| `make clean` | Remove all build artifacts |
