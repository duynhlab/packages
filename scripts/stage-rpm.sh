#!/usr/bin/env bash
# stage-rpm.sh — Extract built tarballs into FHS layout under build/<svc>/staging/
# and render scriptlet templates for nFPM.
#
# Usage: scripts/stage-rpm.sh <svc>
#
# Reads from build/<svc>/raw/  (output of build-local.sh)
# Writes to   build/<svc>/staging/  with this layout:
#   opt/duynhlab/<svc>/bin/<binary>
#   opt/duynhlab/<svc>/BINARY_VERSION
#   opt/duynhlab/<svc>/SCHEMA_VERSION
#   opt/duynhlab/<svc>/migrations/sql/V*.sql
#   etc/duynhlab/<svc>/<svc>.env.template
#   scripts/{preinstall,postinstall,preremove,postremove}.sh

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

[[ $# -eq 1 ]] || die "Usage: $0 <svc>"
SVC=$1
svc_exists "$SVC" || die "Unknown service: $SVC"

TYPE=$(svc_field "$SVC" type)
BINARY=$(svc_field "$SVC" binary)
PORT=$(svc_field "$SVC" port)
DB_NAME=$(svc_field "$SVC" database.name)
APP_USER=$(svc_field "$SVC" database.app_user)
MIGRATOR_USER=$(svc_field "$SVC" database.migrator_user)

[[ $TYPE == backend ]] || die "stage-rpm.sh: only 'backend' supported (got $TYPE for $SVC)"

RAW_DIR="$BUILD_DIR/$SVC/raw"
STAGING="$BUILD_DIR/$SVC/staging"
[[ -d $RAW_DIR ]] || die "Missing raw build dir: $RAW_DIR (run build-local.sh first)"

# Parse version from build-info.env
[[ -f $RAW_DIR/build-info.env ]] || die "Missing $RAW_DIR/build-info.env"
# shellcheck disable=SC1091
. "$RAW_DIR/build-info.env"
: "${VERSION:?VERSION missing in build-info.env}"
: "${GIT_SHA:=unknown}"

log_step "Staging $SVC ($VERSION)"

# Clean staging
rm -rf "$STAGING"
mkdir -p "$STAGING/opt/duynhlab/$SVC/bin" \
         "$STAGING/opt/duynhlab/$SVC/migrations/sql" \
         "$STAGING/etc/duynhlab/$SVC" \
         "$STAGING/scripts"

# Extract binary tarball
BIN_TGZ=$(ls "$RAW_DIR"/${BINARY}-*-linux-amd64.tar.gz | head -1)
[[ -f $BIN_TGZ ]] || die "Binary tarball not found in $RAW_DIR"
tmpd=$(mktemp -d)
tar xzf "$BIN_TGZ" -C "$tmpd"
cp "$tmpd/bin/$BINARY" "$STAGING/opt/duynhlab/$SVC/bin/$BINARY"
chmod 0755 "$STAGING/opt/duynhlab/$SVC/bin/$BINARY"
rm -rf "$tmpd"

# Extract migrations tarball
MIG_TGZ=$(ls "$RAW_DIR"/${BINARY}-*-migrations.tar.gz | head -1)
[[ -f $MIG_TGZ ]] || die "Migrations tarball not found in $RAW_DIR"
tar xzf "$MIG_TGZ" -C "$STAGING/opt/duynhlab/$SVC/migrations/"
# Migrations tarball contains sql/* directly — already at the right path.

# Write version sidecars
echo "$VERSION" > "$STAGING/opt/duynhlab/$SVC/BINARY_VERSION"

SCHEMA_VERSION=$(ls "$STAGING/opt/duynhlab/$SVC/migrations/sql/" 2>/dev/null \
  | sed -n 's/^V\([0-9]\+\)__.*\.sql$/\1/p' \
  | sort -n | tail -1)
[[ -n $SCHEMA_VERSION ]] || SCHEMA_VERSION=0
echo "$SCHEMA_VERSION" > "$STAGING/opt/duynhlab/$SVC/SCHEMA_VERSION"

# Render env template (committed alongside the env file by postinstall)
cat > "$STAGING/etc/duynhlab/$SVC/$SVC.env.template" <<EOF
# /etc/duynhlab/$SVC/$SVC.env.template
# Reference defaults; the live env file is generated at install time with
# a random DB_PASSWORD. Edit /etc/duynhlab/$SVC/$SVC.env to override.

SERVICE_NAME=$SVC
PORT=$PORT

DB_HOST=localhost
DB_PORT=5432
DB_NAME=$DB_NAME
DB_USER=$APP_USER
DB_PASSWORD=__CHANGE_ME__
DB_SSLMODE=disable
DB_POOL_MAX_CONNECTIONS=25

DB_MIGRATOR_USER=$MIGRATOR_USER
DB_MIGRATOR_PASSWORD=__CHANGE_ME__
EOF

# Render scriptlet templates
SCRIPTLET_DIR="$REPO_ROOT/packaging/rpm/scriptlets"
render_scriptlet() {
  local in=$1 out=$2
  sed -e "s/__SERVICE_NAME__/$SVC/g" \
      -e "s/__BINARY_NAME__/$BINARY/g" \
      -e "s/__PORT__/$PORT/g" \
      -e "s/__DB_NAME__/$DB_NAME/g" \
      -e "s/__APP_USER__/$APP_USER/g" \
      "$in" > "$out"
  chmod 0755 "$out"
}

cp "$SCRIPTLET_DIR/preinstall.sh" "$STAGING/scripts/preinstall.sh"
chmod 0755 "$STAGING/scripts/preinstall.sh"
render_scriptlet "$SCRIPTLET_DIR/postinstall.sh.tmpl" "$STAGING/scripts/postinstall.sh"
render_scriptlet "$SCRIPTLET_DIR/preremove.sh.tmpl"   "$STAGING/scripts/preremove.sh"
render_scriptlet "$SCRIPTLET_DIR/postremove.sh.tmpl"  "$STAGING/scripts/postremove.sh"

log_ok "Staged $SVC -> $STAGING (schema v$SCHEMA_VERSION)"
