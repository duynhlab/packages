#!/usr/bin/env bash
# stage-frontend.sh — Extract the frontend dist tarball into FHS staging and
# render scriptlets/nginx vhost for the duynhlab-frontend RPM.
#
# Layout produced under build/frontend/staging/:
#   opt/duynhlab/frontend/dist/...
#   opt/duynhlab/frontend/BINARY_VERSION
#   etc/nginx/conf.d/duynhlab-frontend.conf
#   scripts/{frontend-postinstall,frontend-postremove}.sh

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SVC=frontend
RAW_DIR="$BUILD_DIR/$SVC/raw"
STAGING="$BUILD_DIR/$SVC/staging"
[[ -d $RAW_DIR ]] || die "Missing raw build dir: $RAW_DIR (run build-local.sh frontend)"
[[ -f $RAW_DIR/build-info.env ]] || die "Missing $RAW_DIR/build-info.env"

# shellcheck disable=SC1091
. "$RAW_DIR/build-info.env"
: "${VERSION:?VERSION missing}"

log_step "Staging frontend ($VERSION)"

rm -rf "$STAGING"
mkdir -p "$STAGING/opt/duynhlab/frontend" \
         "$STAGING/etc/nginx/conf.d" \
         "$STAGING/scripts"

TGZ=$(ls "$RAW_DIR"/frontend-*-dist.tar.gz | head -1)
[[ -f $TGZ ]] || die "Frontend dist tarball not found in $RAW_DIR"

# Tarball contains 'dist/...'; extract into opt/duynhlab/frontend/
tar xzf "$TGZ" -C "$STAGING/opt/duynhlab/frontend/"
[[ -d $STAGING/opt/duynhlab/frontend/dist ]] || die "Expected dist/ in tarball"

echo "$VERSION" > "$STAGING/opt/duynhlab/frontend/BINARY_VERSION"

cp "$REPO_ROOT/packaging/rpm/nginx/duynhlab-frontend.conf" \
   "$STAGING/etc/nginx/conf.d/duynhlab-frontend.conf"

cp "$REPO_ROOT/packaging/rpm/scriptlets/frontend-postinstall.sh" "$STAGING/scripts/"
cp "$REPO_ROOT/packaging/rpm/scriptlets/frontend-postremove.sh"  "$STAGING/scripts/"
chmod 0755 "$STAGING/scripts/"*.sh

log_ok "Staged frontend -> $STAGING"
