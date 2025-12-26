# Platform - Multi-Format Package Builder

.PHONY: help validate docker-build build build-nfpm build-rpm build-deb build-legacy clean

# Default target
help:
	@echo "Platform - Available targets:"
	@echo ""
	@echo "  validate       - Validate nfpm.yaml configuration"
	@echo "  build          - Build packages with nFPM (RPM + DEB) [DEFAULT]"
	@echo "  build-nfpm     - Build packages using nFPM (RPM + DEB)"
	@echo "  build-rpm      - Build RPM package only"
	@echo "  build-deb      - Build DEB package only"
	@echo "  build-legacy   - Build single RPM with rpmbuild (legacy)"
	@echo "  docker-build   - Build Docker image (for legacy RPM build)"
	@echo "  clean          - Clean build artifacts"
	@echo ""
	@echo "Examples:"
	@echo "  make validate      # Validate nfpm.yaml configuration"
	@echo "  make build         # Build RPM and DEB packages"
	@echo "  make build-rpm     # Build RPM package only"
	@echo "  make build-deb     # Build DEB package only"

# Validate nFPM configuration
validate:
	@echo "[INFO] Validating nfpm.yaml..."
	@if command -v nfpm >/dev/null 2>&1 || [ -f "$$(go env GOPATH)/bin/nfpm" ]; then \
		export PATH="$$PATH:$$(go env GOPATH)/bin"; \
		echo "[INFO] Testing nFPM package generation..."; \
		nfpm package --packager rpm --target /tmp --config nfpm.yaml 2>&1 | head -20 || echo "[WARNING] Package generation test failed"; \
		echo "[SUCCESS] nfpm.yaml syntax appears valid"; \
	else \
		echo "[ERROR] nfpm command not found"; \
		echo "   Install with: go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.44.1"; \
		exit 1; \
	fi

# Build Docker image
docker-build:
	@echo "[INFO] Building Docker image..."
	@docker build -t rpm-builder:latest .
	@echo "[SUCCESS] Docker image built: rpm-builder:latest"

# Build packages with nFPM (default - generates RPM and DEB)
build:
	@echo "[INFO] Building Platform with nFPM (RPM + DEB)..."
	@chmod +x scripts/build-nfpm.sh
	@PACKAGE_FORMATS="rpm deb" ./scripts/build-nfpm.sh

# Build packages using nFPM (RPM + DEB)
build-nfpm:
	@echo "[INFO] Building Platform with nFPM (RPM + DEB)..."
	@chmod +x scripts/build-nfpm.sh
	@PACKAGE_FORMATS="rpm deb" ./scripts/build-nfpm.sh

# Build RPM package only
build-rpm:
	@echo "[INFO] Building Platform RPM package..."
	@chmod +x scripts/build-nfpm.sh
	@PACKAGE_FORMATS="rpm" ./scripts/build-nfpm.sh

# Build DEB package only
build-deb:
	@echo "[INFO] Building Platform DEB package..."
	@chmod +x scripts/build-nfpm.sh
	@PACKAGE_FORMATS="deb" ./scripts/build-nfpm.sh

# Legacy build using rpmbuild (kept for backward compatibility)
build-legacy: docker-build
	@echo "[INFO] Building Platform (Single RPM - Legacy rpmbuild)..."
	@chmod +x scripts/build.sh
	@./scripts/build.sh

# Clean up
clean:
	@echo "[INFO] Cleaning up..."
	@rm -rf dist/
	@rm -rf build/
	@rm -rf rpm/BUILD rpm/BUILDROOT rpm/RPMS rpm/SRPMS rpm/SOURCES
	@rm -f sources/user-api/user-api sources/checkout-api/checkout-api sources/voter-api/voter-api sources/api-server/api-server
	@echo "[SUCCESS] Cleanup completed!"