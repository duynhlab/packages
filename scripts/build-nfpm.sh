#!/bin/bash

# ============================================================================
# Build nFPM Package Script
# ============================================================================
# Quy trình build:
#   1. Build binary từ sources/{service}/ (source code)
#   2. Prepare TẤT CẢ files vào build/platform/
#   3. Generate packages với nFPM (RPM, DEB, etc.)
#   4. Output: dist/platform-*.{rpm,deb}
# ============================================================================

set -e

# Configuration
SOURCES_DIR="sources"
BUILD_DIR="build/platform"
DIST_DIR="dist"
NFPM_CONFIG="nfpm.yaml"
PACKAGE_FORMATS="${PACKAGE_FORMATS:-rpm deb}"  # Default: build RPM and DEB

echo "[INFO] Building Platform with nFPM..."

# ============================================================================
# Helper Functions
# ============================================================================

# Check if nFPM is installed
check_nfpm() {
    if ! command -v nfpm >/dev/null 2>&1; then
        # Try to find nFPM in Go bin directory
        if [ -n "$GOPATH" ] && [ -f "$GOPATH/bin/nfpm" ]; then
            export PATH="$PATH:$GOPATH/bin"
        elif [ -f "$(go env GOPATH)/bin/nfpm" ]; then
            export PATH="$PATH:$(go env GOPATH)/bin"
        else
            echo "[ERROR] nfpm command not found!" >&2
            echo "   Install with: go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.44.1" >&2
            exit 1
        fi
    fi
    
    echo "[OK] nFPM found: $(nfpm --version 2>&1 | head -n1)"
}

# Validate nFPM configuration
validate_nfpm_config() {
    echo "[INFO] Validating nFPM configuration..."
    if ! nfpm check "$NFPM_CONFIG" >/dev/null 2>&1; then
        echo "[ERROR] nfpm.yaml validation failed!" >&2
        nfpm check "$NFPM_CONFIG"
        exit 1
    fi
    echo "[OK] nFPM configuration is valid"
}

# Auto-detect services (function kept for potential future use)
# Note: Service detection is now done directly in main() function

# Build Go binaries
build_binaries() {
    local services=("$@")
    
    echo "[INFO] Building Go binaries..."
    
    for service in "${services[@]}"; do
        echo "  [INFO] Building $service from $SOURCES_DIR/$service/..."
        
        cd "$SOURCES_DIR/$service"
        go mod tidy
        go build -o "$service" main.go
        cd ../..
        
        echo "  [SUCCESS] $service built successfully"
    done
}

# Prepare files for packaging
prepare_files() {
    local services=("$@")
    
    echo "[INFO] Preparing files for packaging..."
    
    # Clean build directory
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    # Prepare service binaries and configs
    for service in "${services[@]}"; do
        echo "  [INFO] Preparing $service files..."
        
        # Create service directory
        mkdir -p "$BUILD_DIR/apps/$service"
        
        # Copy binary
        if [ -f "$SOURCES_DIR/$service/$service" ]; then
            cp "$SOURCES_DIR/$service/$service" "$BUILD_DIR/apps/$service/"
            chmod +x "$BUILD_DIR/apps/$service/$service"
        else
            echo "  [WARNING] Binary not found for $service" >&2
        fi
        
        # Copy service config
        if [ -f "configs/apps/$service/$service.properties" ]; then
            cp "configs/apps/$service/$service.properties" "$BUILD_DIR/apps/$service/"
            chmod 644 "$BUILD_DIR/apps/$service/$service.properties"
        fi
    done
    
    # Copy shared configs
    echo "  [INFO] Copying shared configs..."
    mkdir -p "$BUILD_DIR/apps/common"
    if [ -d "configs/apps/common" ]; then
        cp configs/apps/common/*.properties "$BUILD_DIR/apps/common/" 2>/dev/null || true
        chmod 644 "$BUILD_DIR/apps/common"/*.properties 2>/dev/null || true
    fi
    
    # Copy infrastructure configs
    echo "  [INFO] Copying infrastructure configs..."
    mkdir -p "$BUILD_DIR/infra/nginx"
    mkdir -p "$BUILD_DIR/infra/redis"
    if [ -f "configs/infra/nginx/platform.conf" ]; then
        cp configs/infra/nginx/platform.conf "$BUILD_DIR/infra/nginx/"
        chmod 644 "$BUILD_DIR/infra/nginx/platform.conf"
    fi
    if [ -f "configs/infra/redis/platform-redis.conf" ]; then
        cp configs/infra/redis/platform-redis.conf "$BUILD_DIR/infra/redis/"
        chmod 644 "$BUILD_DIR/infra/redis/platform-redis.conf"
    fi
    
    # Copy systemd files
    echo "  [INFO] Copying systemd files..."
    mkdir -p "$BUILD_DIR/systemd"
    if [ -d "rpm/files/systemd" ]; then
        cp rpm/files/systemd/* "$BUILD_DIR/systemd/" 2>/dev/null || true
        chmod 644 "$BUILD_DIR/systemd"/* 2>/dev/null || true
    fi
    
    # Copy initialization scripts
    echo "  [INFO] Copying initialization scripts..."
    mkdir -p "$BUILD_DIR/lib"
    if [ -d "rpm/platform/lib" ]; then
        cp rpm/platform/lib/*.sh "$BUILD_DIR/lib/" 2>/dev/null || true
        chmod +x "$BUILD_DIR/lib"/*.sh 2>/dev/null || true
    fi
    
    echo "[SUCCESS] Files prepared successfully"
}

# Generate packages with nFPM
build_packages() {
    local formats=($PACKAGE_FORMATS)
    
    echo "[INFO] Generating packages with nFPM..."
    
    # Show files that will be packaged (similar to rpmbuild verbose output)
    echo "[INFO] Files to be packaged:"
    if [ -d "$BUILD_DIR" ]; then
        find "$BUILD_DIR" -type f | sort | while read -r file; do
            rel_path="${file#$BUILD_DIR/}"
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "?")
            perms=$(stat -f%Sp "$file" 2>/dev/null || stat -c%a "$file" 2>/dev/null || echo "?")
            echo "    $rel_path (size: $size bytes, perms: $perms)"
        done
        file_count=$(find "$BUILD_DIR" -type f | wc -l | tr -d ' ')
        echo "[INFO] Total files to package: $file_count"
    else
        echo "    [WARNING] Build directory not found: $BUILD_DIR"
    fi
    echo ""
    
    # Create dist directory
    mkdir -p "$DIST_DIR"
    
    for format in "${formats[@]}"; do
        echo "  [INFO] Building $format package..."
        
        if nfpm pkg \
            --packager "$format" \
            --target "$DIST_DIR/" \
            --config "$NFPM_CONFIG" \
            >/dev/null 2>&1; then
            echo "  [SUCCESS] $format package built successfully"
        else
            echo "  [ERROR] Failed to build $format package" >&2
            # Show error output
            nfpm pkg \
                --packager "$format" \
                --target "$DIST_DIR/" \
                --config "$NFPM_CONFIG"
            exit 1
        fi
    done
    
    echo ""
    echo "[SUCCESS] Packages built successfully:"
    ls -lh "$DIST_DIR"/platform-*.* 2>/dev/null || true
}

# ============================================================================
# Main Build Process
# ============================================================================

main() {
    # Check prerequisites
    check_nfpm
    validate_nfpm_config
    
    # Detect services
    local services=()
    for dir in "$SOURCES_DIR"/*/; do
        if [ -d "$dir" ] && [ -f "$dir/main.go" ]; then
            service_name=$(basename "$dir")
            services+=("$service_name")
        fi
    done
    
    if [ ${#services[@]} -eq 0 ]; then
        echo "[ERROR] No services found in $SOURCES_DIR/ directory!" >&2
        echo "   Please add service code in $SOURCES_DIR/{service-name}/ with main.go" >&2
        exit 1
    fi
    
    echo "[OK] Found services: ${services[*]}"
    
    # Build binaries
    build_binaries "${services[@]}"
    
    # Prepare files
    prepare_files "${services[@]}"
    
    # Generate packages
    build_packages
    
    echo ""
    echo "[SUCCESS] Platform packages created!"
    echo ""
    echo "[INFO] Install packages:"
    echo "  RPM: sudo dnf install $DIST_DIR/platform-*.rpm"
    echo "  DEB: sudo dpkg -i $DIST_DIR/platform-*.deb"
    echo ""
    echo "[INFO] Access: http://localhost:80/"
    echo "[INFO] Control: systemctl start/stop platform-all.target"
}

# Execute main function
main "$@"
