#!/usr/bin/env bash
# build-common.sh — Stage build/common/staging for the duynhlab-common RPM.
#
# Downloads golang-migrate, lays out common-scriptlets, and prepares everything
# nfpm-common.tmpl.yaml expects. Idempotent.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

MIGRATE_VERSION=${MIGRATE_VERSION:-v4.17.0}
MIGRATE_URL="https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VERSION}/migrate.linux-amd64.tar.gz"

STAGING="$BUILD_DIR/common/staging"
log_step "Staging common -> $STAGING"

rm -rf "$STAGING"
mkdir -p "$STAGING/usr/bin" "$STAGING/scripts"

# Download golang-migrate (cached under build/common/cache)
CACHE_DIR="$BUILD_DIR/common/cache"
mkdir -p "$CACHE_DIR"
CACHE_TGZ="$CACHE_DIR/migrate-${MIGRATE_VERSION}.tar.gz"
if [[ ! -s $CACHE_TGZ ]]; then
  log_info "Downloading golang-migrate $MIGRATE_VERSION"
  require_cmd curl
  curl -fsSL --retry 3 -o "$CACHE_TGZ.tmp" "$MIGRATE_URL"
  mv "$CACHE_TGZ.tmp" "$CACHE_TGZ"
else
  log_info "Using cached migrate tarball: $CACHE_TGZ"
fi

tmpd=$(mktemp -d)
tar xzf "$CACHE_TGZ" -C "$tmpd"
# The archive ships a single 'migrate' binary.
[[ -x $tmpd/migrate ]] || die "migrate binary not found in $CACHE_TGZ"
cp "$tmpd/migrate" "$STAGING/usr/bin/duynhlab-db-migrate"
chmod 0755 "$STAGING/usr/bin/duynhlab-db-migrate"
rm -rf "$tmpd"

# Copy common scriptlets
SCRIPTLET_DIR="$REPO_ROOT/packaging/rpm/scriptlets"
cp "$SCRIPTLET_DIR/common-preinstall.sh"  "$STAGING/scripts/common-preinstall.sh"
cp "$SCRIPTLET_DIR/common-postinstall.sh" "$STAGING/scripts/common-postinstall.sh"
cp "$SCRIPTLET_DIR/common-postremove.sh"  "$STAGING/scripts/common-postremove.sh"
chmod 0755 "$STAGING/scripts/"*.sh

log_ok "Common staged ($MIGRATE_VERSION)"
