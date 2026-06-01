#!/usr/bin/env bash
# render-nfpm.sh — Render an nfpm.yaml from the per-service/common/platform templates.
#
# Usage:
#   scripts/render-nfpm.sh service <svc>      -> build/<svc>/nfpm.yaml
#   scripts/render-nfpm.sh common             -> build/common/nfpm.yaml
#   scripts/render-nfpm.sh platform           -> build/platform/nfpm.yaml
#
# Paths inside the rendered nfpm.yaml are RELATIVE to REPO_ROOT so the file
# works both on the host and when REPO_ROOT is mounted as /work in a container.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_cmd envsubst

KIND=${1:-}
[[ -n $KIND ]] || die "Usage: $0 {service <svc>|common|platform}"

RELEASE=${RELEASE:-1.el9}

case $KIND in
  service)
    SVC=${2:-}
    [[ -n $SVC ]] || die "Usage: $0 service <svc>"
    svc_exists "$SVC" || die "Unknown service: $SVC"
    BINARY=$(svc_field "$SVC" binary)
    # Pull VERSION from build-info.env
    BUILD_INFO="$BUILD_DIR/$SVC/raw/build-info.env"
    [[ -f $BUILD_INFO ]] || die "Missing $BUILD_INFO"
    # shellcheck disable=SC1090
    . "$BUILD_INFO"
    # nFPM disallows '+' in version strings even with version_schema:none;
    # convert local SemVer build metadata to '-'.
    VERSION=${VERSION//+/-}
    OUT="$BUILD_DIR/$SVC/nfpm.yaml"
    mkdir -p "$(dirname "$OUT")"
    SERVICE_NAME=$SVC \
    BINARY_NAME=$BINARY \
    VERSION=$VERSION \
    RELEASE=$RELEASE \
    STAGING_DIR="build/$SVC/staging" \
    SYSTEMD_DIR="build/systemd" \
      envsubst '${SERVICE_NAME} ${BINARY_NAME} ${VERSION} ${RELEASE} ${STAGING_DIR} ${SYSTEMD_DIR}' \
      < "$REPO_ROOT/packaging/rpm/nfpm.tmpl.yaml" > "$OUT"
    log_ok "Rendered $OUT ($SVC $VERSION)"
    ;;

  common)
    VERSION=${VERSION:-$(date -u +%Y.%m.%d)}
    VERSION=${VERSION//+/-}
    OUT="$BUILD_DIR/common/nfpm.yaml"
    mkdir -p "$(dirname "$OUT")"
    VERSION=$VERSION \
    RELEASE=$RELEASE \
    STAGING_DIR="build/common/staging" \
    COMMON_SRC="packaging/common/scripts" \
    SERVICES_YAML="services.yaml" \
    SYSTEMD_DIR="build/systemd" \
      envsubst '${VERSION} ${RELEASE} ${STAGING_DIR} ${COMMON_SRC} ${SERVICES_YAML} ${SYSTEMD_DIR}' \
      < "$REPO_ROOT/packaging/rpm/nfpm-common.tmpl.yaml" > "$OUT"
    log_ok "Rendered $OUT (common $VERSION)"
    ;;

  frontend)
    BUILD_INFO="$BUILD_DIR/frontend/raw/build-info.env"
    [[ -f $BUILD_INFO ]] || die "Missing $BUILD_INFO"
    # shellcheck disable=SC1090
    . "$BUILD_INFO"
    VERSION=${VERSION//+/-}
    OUT="$BUILD_DIR/frontend/nfpm.yaml"
    mkdir -p "$(dirname "$OUT")"
    VERSION=$VERSION \
    RELEASE=$RELEASE \
    STAGING_DIR="build/frontend/staging" \
      envsubst '${VERSION} ${RELEASE} ${STAGING_DIR}' \
      < "$REPO_ROOT/packaging/rpm/nfpm-frontend.tmpl.yaml" > "$OUT"
    log_ok "Rendered $OUT (frontend $VERSION)"
    ;;

  platform)
    VERSION=${VERSION:-$(date -u +%Y.%m.%d)}
    VERSION=${VERSION//+/-}
    OUT="$BUILD_DIR/platform/nfpm.yaml"
    mkdir -p "$(dirname "$OUT")"
    VERSION=$VERSION \
    RELEASE=$RELEASE \
      envsubst '${VERSION} ${RELEASE}' \
      < "$REPO_ROOT/packaging/rpm/nfpm-platform.tmpl.yaml" > "$OUT"
    log_ok "Rendered $OUT (platform $VERSION)"
    ;;

  *)
    die "Unknown kind: $KIND"
    ;;
esac
