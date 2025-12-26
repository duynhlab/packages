#!/bin/bash

# ============================================================================
# Build Single RPM Script (Legacy - uses rpmbuild)
# ============================================================================
# Quy trình build:
#   1. Build binary từ sources/{service}/ (source code)
#   2. Copy binary vào configs/apps/{service}/ (staging area)
#   3. Copy TẤT CẢ files vào rpm/SOURCES/ (RPM input)
#   4. Build RPM trong Docker container sử dụng rpmbuild
#   5. Output: dist/platform-*.rpm
#
# NOTE: Đây là legacy build script sử dụng rpmbuild.
#       Để build multi-format (RPM, DEB), sử dụng: make build-nfpm
# ============================================================================

set -e

echo "[INFO] Building Platform (Legacy RPM build with rpmbuild)..."

# ============================================================================
# STEP 1: Build Binaries từ Source Code cho TẤT CẢ Services có sẵn trong sources/
# ============================================================================
# Input:  sources/{service}/ (source code - có sẵn trong sources/)
# Output: sources/{service}/{service} (binary file cho mỗi service)
# 
# NOTE: Script tự động detect và build các service có trong sources/
#       Chỉ build những service có code sẵn, không cần clone
#       Mỗi service phải có main.go trong thư mục của nó
# ============================================================================
echo "[INFO] Building all services from sources/..."

# Auto-detect services in sources/ directory
# Tìm tất cả thư mục con trong sources/ có chứa main.go
services=()
for dir in sources/*/; do
    if [ -d "$dir" ] && [ -f "$dir/main.go" ]; then
        service_name=$(basename "$dir")
        services+=("$service_name")
    fi
done

# Kiểm tra xem có service nào được tìm thấy không
if [ ${#services[@]} -eq 0 ]; then
    echo "[ERROR] No services found in sources/ directory!"
    echo "   Please add service code in sources/{service-name}/ with main.go"
    exit 1
fi

echo "[INFO] Found services: ${services[*]}"

# Build từng service
for service in "${services[@]}"; do
    echo "[INFO] Building $service from sources/$service/..."
    
    # Di chuyển vào thư mục service để build
    cd "sources/$service"
    
    # Tải dependencies và build binary
    go mod tidy
    go build -o "$service" main.go
    
    # Quay lại thư mục gốc
    cd ../..
    
    echo "[SUCCESS] $service built successfully"
done

# ============================================================================
# STEP 2: Copy Binaries vào configs/apps/ (Staging Area)
# ============================================================================
# Input:  sources/{service}/{service} (binary vừa build xong)
# Output: configs/apps/{service}/{service} (binary được copy vào staging area)
#
# NOTE: Binaries được copy vào configs/apps/ để tách biệt với source code
#       Đây là staging area trước khi copy vào rpm/SOURCES/
# ============================================================================
echo "[INFO] Copying binaries to configs/apps/ (staging area)..."

for service in "${services[@]}"; do
    echo "[INFO] Copying $service binary to configs/apps/$service/..."
    
    # Tạo thư mục nếu chưa có
    mkdir -p "configs/apps/$service"
    
    # Copy binary từ sources/ sang configs/apps/
    cp "sources/$service/$service" "configs/apps/$service/"
done

# ============================================================================
# STEP 3: Prepare RPM SOURCES - Copy TẤT CẢ files cần thiết
# ============================================================================
# RPM cần tất cả files trong rpm/SOURCES/ để build
# Files này sẽ được đọc bởi rpm/specs/platform.spec trong Docker container
#
# Các files cần copy:
#   - Binaries: từ configs/apps/{service}/
#   - Configs: từ configs/apps/common/ và configs/apps/{service}/
#   - Infra configs: từ configs/infra/
#   - Systemd files: từ rpm/files/systemd/
#   - Scripts: từ rpm/platform/lib/
# ============================================================================
echo "[INFO] Preparing RPM sources..."

# Clean previous build artifacts để tránh conflict
rm -rf rpm/SOURCES/*
mkdir -p rpm/SOURCES

# 3.1: Copy Binaries (từ configs/apps/{service}/)
# Binaries đã được copy vào configs/apps/ ở STEP 2
echo "[INFO] Copying binaries..."
for service in "${services[@]}"; do
    mkdir -p "rpm/SOURCES/$service" || true
    
    # Copy binary từ configs/apps/ (KHÔNG phải từ apps/)
    if [ -f "configs/apps/$service/$service" ]; then
        cp "configs/apps/$service/$service" "rpm/SOURCES/$service/"
        echo "    [OK] Copied $service binary"
    else
        echo "    [WARNING] Binary not found for $service: configs/apps/$service/$service"
    fi
done

# 3.2: Copy Shared Configs (từ configs/apps/common/)
# Shared configs được dùng chung bởi tất cả services
echo "[INFO] Copying shared configs..."
mkdir -p rpm/SOURCES/conf
if [ -d "configs/apps/common" ] && [ "$(ls -A configs/apps/common/*.properties 2>/dev/null)" ]; then
    cp configs/apps/common/*.properties rpm/SOURCES/conf/
    # Fix permissions: remove executable bit from .properties files
    chmod 644 rpm/SOURCES/conf/*.properties
    echo "    [OK] Copied shared configs"
else
    echo "    [WARNING] No shared configs found in configs/apps/common/"
fi

# 3.3: Copy App-specific Configs (từ configs/apps/{service}/)
# Mỗi service có config riêng của nó
echo "[INFO] Copying app-specific configs..."
for service in "${services[@]}"; do
    # Directory đã được tạo ở 3.1, chỉ cần copy config
    if [ -f "configs/apps/$service/$service.properties" ]; then
        cp "configs/apps/$service/$service.properties" "rpm/SOURCES/$service/"
        # Fix permissions: remove executable bit
        chmod 644 "rpm/SOURCES/$service/$service.properties"
        echo "    [OK] Copied $service config"
    else
        echo "    [WARNING] Config not found for $service: configs/apps/$service/$service.properties"
    fi
done

# 3.4: Copy Infrastructure Configs (từ configs/infra/)
# Nginx và Redis configuration files
echo "[INFO] Copying infrastructure configs..."
if [ -f "configs/infra/nginx/platform.conf" ]; then
    cp configs/infra/nginx/platform.conf rpm/SOURCES/
    echo "    [OK] Copied nginx config"
else
    echo "    [WARNING] Nginx config not found: configs/infra/nginx/platform.conf"
fi

if [ -f "configs/infra/redis/platform-redis.conf" ]; then
    cp configs/infra/redis/platform-redis.conf rpm/SOURCES/
    echo "    [OK] Copied redis config"
else
    echo "    [WARNING] Redis config not found: configs/infra/redis/platform-redis.conf"
fi

# 3.5: Copy Systemd Service Files (từ rpm/files/systemd/)
# Systemd unit files (.service và .target)
echo "[INFO] Copying systemd files..."
if [ -d "rpm/files/systemd" ] && [ "$(ls -A rpm/files/systemd/* 2>/dev/null)" ]; then
    cp rpm/files/systemd/* rpm/SOURCES/
    echo "    [OK] Copied systemd files"
else
    echo "    [WARNING] No systemd files found in rpm/files/systemd/"
fi

# 3.6: Copy Initialization Scripts (từ rpm/platform/lib/)
# Scripts chạy khi install/upgrade package
echo "[INFO] Copying initialization scripts..."
if [ -d "rpm/platform/lib" ]; then
    cp rpm/platform/lib/*.sh rpm/SOURCES/ 2>/dev/null || true
    if [ $? -eq 0 ]; then
        echo "    [OK] Copied initialization scripts"
    else
        echo "    [WARNING] No .sh files found in rpm/platform/lib/"
    fi
else
    echo "    [WARNING] Directory not found: rpm/platform/lib/"
fi

echo "[SUCCESS] RPM sources prepared successfully"

# ============================================================================
# STEP 4: Build RPM trong Docker Container
# ============================================================================
# Input:  rpm/SOURCES/ (tất cả files đã được copy ở STEP 3)
#         rpm/specs/platform.spec (RPM specification file)
# Output: dist/platform-*.rpm (RPM package)
#
# NOTE: Sử dụng Docker container với rpmbuild để build RPM
#       Container image: rpm-builder:latest (cần build trước với make docker-build)
#       RPM spec file định nghĩa cách package được build và install
# ============================================================================
echo "[INFO] Building single RPM in Docker container..."

# Kiểm tra xem Docker image đã được build chưa
if ! docker images | grep -q "rpm-builder.*latest"; then
    echo "[WARNING] Docker image 'rpm-builder:latest' not found!"
    echo "   Building Docker image first..."
    docker build -t rpm-builder:latest .
fi

# Build RPM trong Docker container
# Mount các thư mục cần thiết vào container
docker run --rm \
    -v "$(pwd)/rpm/SOURCES:/workspace/SOURCES" \
    -v "$(pwd)/rpm/specs:/workspace/specs" \
    -v "$(pwd)/dist:/workspace/dist" \
    -w /workspace \
    rpm-builder:latest \
    bash -c '
        # Build RPM package
        rpmbuild -bb \
            --define "_sourcedir /workspace/SOURCES" \
            --define "_specdir /workspace/specs" \
            --define "_builddir /workspace/BUILD" \
            --define "_srcrpmdir /workspace/SRPMS" \
            --define "_rpmdir /workspace/RPMS" \
            --define "_buildrootdir /workspace/BUILDROOT" \
            /workspace/specs/platform.spec
        
        # Copy RPM từ container ra dist/ directory
        find RPMS -name "*.rpm" -exec cp {} /workspace/dist/ \;
    '

# Kiểm tra kết quả
if [ -f dist/platform-*.rpm ]; then
    echo "[SUCCESS] Single RPM built successfully:"
    ls -lh dist/platform-*.rpm
    
    echo ""
    echo "[SUCCESS] Platform RPM created!"
    echo "[INFO] Install: sudo dnf install dist/platform-*.rpm"
    echo "[INFO] Access: http://localhost:80/"
    echo "[INFO] Control: systemctl start/stop platform-all.target"
else
    echo "[ERROR] RPM package not found in dist/ directory!"
    exit 1
fi
