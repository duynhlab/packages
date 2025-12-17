#!/bin/bash

# ============================================================================
# Build Single RPM Script
# ============================================================================
# Quy trình build:
#   1. Build binary từ repo/api-server/ (source code)
#   2. Copy binary vào apps/api-server/ (staging)
#   3. Copy TẤT CẢ files vào rpm/SOURCES/ (RPM input)
#   4. Build RPM trong Docker container
#   5. Output: dist/platform-*.rpm
# ============================================================================

set -e

echo "🚀 Building Platform..."

# ============================================================================
# STEP 1: Build Binaries từ Source Code cho TẤT CẢ Services có sẵn trong repo/
# ============================================================================
# Input:  repo/{service}/ (source code - có sẵn trong repo/)
# Output: repo/{service}/{service} (binary file cho mỗi service)
# 
# NOTE: Script tự động detect và build các service có trong repo/
#       Chỉ build những service có code sẵn, không cần clone
# ============================================================================
echo "📝 Building all services from repo/..."

# Auto-detect services in repo/ directory
services=()
for dir in repo/*/; do
    if [ -d "$dir" ] && [ -f "$dir/main.go" ]; then
        service_name=$(basename "$dir")
        services+=("$service_name")
    fi
done

if [ ${#services[@]} -eq 0 ]; then
    echo "❌ Error: No services found in repo/ directory!"
    echo "   Please add service code in repo/{service-name}/ with main.go"
    exit 1
fi

echo "🔍 Found services: ${services[*]}"

# Build each service
for service in "${services[@]}"; do
    echo "🔨 Building $service from repo/$service/..."
    
    cd "repo/$service"
    go mod tidy
    go build -o "$service" main.go
    cd ../..
    
    echo "✅ $service built successfully"
done

# ============================================================================
# STEP 2: Copy Binaries vào apps/ (Staging Area)
# ============================================================================
# Input:  repo/{service}/{service} (binary)
# Output: apps/{service}/{service} (binary)
# ============================================================================
echo "📦 Copying binaries to apps/..."

for service in "${services[@]}"; do
    echo "📦 Copying $service binary to apps/$service/..."
    mkdir -p "apps/$service"
    cp "repo/$service/$service" "apps/$service/"
done

# ============================================================================
# STEP 3: Prepare RPM SOURCES - Copy TẤT CẢ files cần thiết
# ============================================================================
# RPM cần tất cả files trong rpm/SOURCES/ để build
# Files này sẽ được đọc bởi rpm/specs/platform.spec
# ============================================================================
echo "📦 Preparing RPM sources..."
# Clean previous build artifacts
rm -rf rpm/SOURCES/*
mkdir -p rpm/SOURCES

# 3.1: Binaries (từ apps/{service}/)
for service in "${services[@]}"; do
    mkdir -p "rpm/SOURCES/$service" || true
    if [ -f "apps/$service/$service" ]; then
        cp "apps/$service/$service" "rpm/SOURCES/$service/"
    fi
done

# 3.2: Shared configs (từ apps/conf/)
mkdir -p rpm/SOURCES/conf
cp apps/conf/*.properties rpm/SOURCES/conf/
# Fix permissions: remove executable bit from .properties files
chmod 644 rpm/SOURCES/conf/*.properties

# 3.3: App-specific configs (từ apps/{service}/)
for service in "${services[@]}"; do
    # Directory already created in 3.1, just copy config
    if [ -f "apps/$service/$service.properties" ]; then
        cp "apps/$service/$service.properties" "rpm/SOURCES/$service/"
        # Fix permissions: remove executable bit
        chmod 644 "rpm/SOURCES/$service/$service.properties"
    fi
done

# 3.4: Infrastructure configs (từ infra/)
cp infra/nginx/platform.conf rpm/SOURCES/
cp infra/redis/platform-redis.conf rpm/SOURCES/

# 3.5: Systemd service files (từ rpm/files/systemd/)
cp rpm/files/systemd/* rpm/SOURCES/

# 3.6: Initialization scripts (từ rpm/platform/lib/)
if [ -d "rpm/platform/lib" ]; then
    cp rpm/platform/lib/*.sh rpm/SOURCES/ 2>/dev/null || true
fi

# ============================================================================
# STEP 4: Build RPM trong Docker Container
# ============================================================================
# Input:  rpm/SOURCES/ (tất cả files)
#         rpm/specs/platform.spec (RPM specification)
# Output: dist/platform-*.rpm (RPM package)
# ============================================================================
echo "📦 Building single RPM..."
docker run --rm \
    -v "$(pwd)/rpm/SOURCES:/workspace/SOURCES" \
    -v "$(pwd)/rpm/specs:/workspace/specs" \
    -v "$(pwd)/dist:/workspace/dist" \
    -w /workspace \
    rpm-builder:latest \
    bash -c '
        rpmbuild -bb \
            --define "_sourcedir /workspace/SOURCES" \
            --define "_specdir /workspace/specs" \
            --define "_builddir /workspace/BUILD" \
            --define "_srcrpmdir /workspace/SRPMS" \
            --define "_rpmdir /workspace/RPMS" \
            --define "_buildrootdir /workspace/BUILDROOT" \
            specs/platform.spec
        
        # Copy RPM to dist
        find RPMS -name "*.rpm" -exec cp {} /workspace/dist/ \;
    '

echo "✅ Single RPM built:"
ls -la dist/platform-*.rpm

echo ""
echo "🎉 Platform RPM created!"
echo "📦 Install: rpm -ivh dist/platform-*.rpm"
echo "🌐 Access: http://localhost:80/"
echo "🔧 Control: systemctl start/stop platform-all.target"