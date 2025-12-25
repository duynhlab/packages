# Getting Started

This guide will help you get started with the Platform RPM Builder project, from initial setup to adding your own services.

## Prerequisites

Before you begin, ensure you have the following installed:

- **Go 1.25+** - Required for building service binaries
- **Docker** - Required for building RPM packages in a clean environment
- **Rocky Linux 9** (or compatible RHEL-based distribution) - For running the build container
- **Git** - For cloning repositories
- **Make** - For running build commands

### Verify Prerequisites

```bash
# Check Go version
go version  # Should show go1.25 or higher

# Check Docker
docker --version

# Check Make
make --version
```

## Quick Start

### 1. Clone the Repository

```bash
git clone <repository-url>
cd rpm-builder
```

### 2. Build the RPM

```bash
# Build Docker image and create RPM package
make build
```

This will:
- Build Docker image with RPM build tools
- Compile all Go services from `repo/`
- Package everything into a single RPM file
- Output: `dist/platform-1.0.0-1.x86_64.rpm`

### 3. Install the RPM

```bash
# Install on target system
sudo dnf install dist/platform-1.0.0-1.x86_64.rpm
```

### 4. Start Services

```bash
# Start all platform services
sudo systemctl start platform-all.target

# Check status
sudo systemctl status platform-all.target
```

## Adding a New Service

This section walks you through adding a new Go service to the platform.

### Step 1: Create Service Source Code

Create a new directory in `repo/` for your service:

```bash
mkdir -p repo/payment-api
cd repo/payment-api
```

Create a basic Go service structure:

**main.go:**
```go
package main

import (
    "fmt"
    "log"
    "net/http"
    "os"
)

func main() {
    port := os.Getenv("PORT")
    if port == "" {
        port = "8083"
    }

    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "Payment API is running on port %s", port)
    })

    http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        fmt.Fprint(w, "OK")
    })

    log.Printf("Payment API starting on port %s", port)
    log.Fatal(http.ListenAndServe(":"+port, nil))
}
```

**go.mod:**
```go
module payment-api

go 1.25
```

### Step 2: Add Service Configuration

Create configuration file in `apps/payment-api/`:

```bash
mkdir -p apps/payment-api
```

**apps/payment-api/payment-api.properties:**
```properties
PORT=8083
LOG_LEVEL=info
```

### Step 3: Create Systemd Service File

Create systemd service file in `rpm/files/systemd/`:

**rpm/files/systemd/platform-payment-api.service:**
```ini
[Unit]
Description=Platform - Payment API
After=platform-infra.target
Requires=platform-infra.target
PartOf=platform-all.target

[Service]
Type=exec
User=nobody
Group=nobody
WorkingDirectory=/opt/platform/apps/payment-api

# Load shared configurations
EnvironmentFile=/opt/platform/apps/conf/env.properties
EnvironmentFile=/opt/platform/apps/conf/redis.properties

# Load app-specific configuration
EnvironmentFile=/opt/platform/apps/payment-api/payment-api.properties

ExecStart=/opt/platform/apps/payment-api/payment-api
Restart=always
RestartSec=10
StandardOutput=append:/var/log/platform/payment-api/stdout.log
StandardError=append:/var/log/platform/payment-api/stderr.log

[Install]
WantedBy=multi-user.target
```

### Step 4: Update RPM Spec File

Edit `rpm/specs/platform.spec` to include your new service:

**Add to %install section:**
```spec
# Create directory for payment-api
mkdir -p %{buildroot}/opt/platform/apps/payment-api/

# Copy payment-api binary
cp %{_sourcedir}/payment-api/payment-api %{buildroot}/opt/platform/apps/payment-api/

# Copy payment-api configuration
cp %{_sourcedir}/payment-api/payment-api.properties %{buildroot}/opt/platform/apps/payment-api/
```

**Add to %files section:**
```spec
# Payment API
/opt/platform/apps/payment-api/payment-api
%config(noreplace) /opt/platform/apps/payment-api/payment-api.properties
```

**Add to %pre section (log directory):**
```spec
mkdir -p /var/log/platform/payment-api
```

**Add to %post section (executable permissions):**
```spec
chmod +x /opt/platform/apps/payment-api/payment-api
```

**Update platform-all.target in %files:**
The systemd target file will automatically include your service if it's in the Wants list.

### Step 5: Update platform-all.target

Edit `rpm/files/systemd/platform-all.target`:

```ini
[Unit]
Description=Platform All Services
After=platform-infra.target
Wants=platform-api-server.service platform-user-api.service platform-checkout-api.service platform-voter-api.service platform-payment-api.service

[Install]
WantedBy=multi-user.target
```

### Step 6: Build and Test

```bash
# Clean previous build
make clean

# Build with new service
make build

# Install and test
sudo dnf install dist/platform-*.rpm
sudo systemctl start platform-all.target
sudo systemctl status platform-payment-api.service
```

## Common Tasks

### Building for Specific Services Only

The build script automatically detects all services in `repo/` with `main.go`. To build only specific services:

1. Temporarily move or rename other service directories
2. Run `make build`
3. Restore directories

### Updating Service Configuration

1. Edit configuration file in `apps/{service}/{service}.properties`
2. Rebuild RPM: `make build`
3. Upgrade installation: `sudo dnf upgrade dist/platform-*.rpm`

### Viewing Service Logs

```bash
# View service logs
sudo journalctl -u platform-user-api.service -f

# View log files
tail -f /var/log/platform/user-api/stdout.log
tail -f /var/log/platform/user-api/stderr.log
```

### Stopping and Starting Services

```bash
# Stop all platform services
sudo systemctl stop platform-all.target

# Start all platform services
sudo systemctl start platform-all.target

# Restart a specific service
sudo systemctl restart platform-user-api.service
```

### Uninstalling the Platform

```bash
# Stop services first
sudo systemctl stop platform-all.target
sudo systemctl disable platform-all.target

# Remove RPM package
sudo dnf remove platform
```

**Note:** This will remove all platform files including:
- Service binaries in `/opt/platform/apps/`
- Configuration files in `/opt/platform/apps/`
- Systemd service files
- Log directories in `/var/log/platform/`

### Reinstalling the Platform

After uninstalling, you can reinstall the platform:

```bash
# Uninstall existing installation (if any)
sudo systemctl stop platform-all.target || true
sudo systemctl disable platform-all.target || true
sudo dnf remove platform || true

# Clean up any remaining files (optional)
sudo rm -rf /opt/platform
sudo rm -rf /var/log/platform
sudo rm -f /etc/nginx/conf.d/platform.conf
sudo rm -f /etc/redis/platform-redis.conf

# Reinstall from RPM
sudo dnf install dist/platform-*.rpm

# Verify installation
sudo systemctl status platform-all.target
```

### Upgrading the Platform

To upgrade to a new version:

```bash
# Upgrade using dnf (recommended)
sudo dnf upgrade dist/platform-*.rpm

# Or install new version (will replace old version)
sudo dnf install dist/platform-*.rpm

# Restart services to apply changes
sudo systemctl restart platform-all.target
```

**Note:** Configuration files marked with `%config(noreplace)` in the spec file will be preserved during upgrades. If you want to use new default configurations, backup your current configs first:

```bash
# Backup current configurations
sudo cp -r /opt/platform/apps/conf /opt/platform/apps/conf.backup
sudo cp /opt/platform/apps/*/ *.properties /opt/platform/apps/conf.backup/

# Upgrade
sudo dnf upgrade dist/platform-*.rpm

# Restore configurations if needed
sudo cp /opt/platform/apps/conf.backup/* /opt/platform/apps/conf/
```

## Troubleshooting

### Build Fails with "No services found"

**Problem:** Build script can't find services in `repo/`

**Solution:**
- Ensure each service directory has a `main.go` file
- Check that service directories are directly under `repo/`
- Verify directory structure: `repo/{service-name}/main.go`

### Go Build Errors

**Problem:** `go build` fails with module errors

**Solution:**
```bash
# Navigate to service directory
cd repo/{service-name}

# Download dependencies
go mod tidy

# Try building again
go build -o {service-name} main.go
```

### Docker Build Fails

**Problem:** Docker image build fails

**Solution:**
```bash
# Check Docker is running
docker ps

# Rebuild Docker image
make docker-build

# Check for errors in Docker output
```

### RPM Installation Fails

**Problem:** `dnf install` fails with dependency errors

**Solution:**
```bash
# Install dependencies manually first
sudo dnf install nginx redis systemd

# Then install RPM
sudo dnf install dist/platform-*.rpm
```

### Services Don't Start

**Problem:** Services fail to start after installation

**Solution:**
```bash
# Check service status
sudo systemctl status platform-all.target

# Check individual service
sudo systemctl status platform-user-api.service

# View logs
sudo journalctl -u platform-user-api.service

# Check port availability
sudo ss -tuln | grep -E ":(80|6379|8079|8080|8081|8082)"
```

### Port Already in Use

**Problem:** Installation fails because ports are already in use

**Solution:**
```bash
# Find process using the port
sudo lsof -i :8080

# Stop the conflicting service
sudo systemctl stop <conflicting-service>

# Or change port in service configuration
```

### Configuration Not Applied

**Problem:** Service doesn't use updated configuration

**Solution:**
```bash
# Reload systemd configuration
sudo systemctl daemon-reload

# Restart service
sudo systemctl restart platform-user-api.service

# Verify environment variables
sudo systemctl show platform-user-api.service | grep EnvironmentFile
```

## Next Steps

- Read [Build Process](build-process.md) for detailed build flow
- Check [Directory Structure](directory-structure.md) to understand project layout
- Review `rpm/specs/platform.spec` to understand RPM packaging
- Explore `scripts/build.sh` to customize build process

