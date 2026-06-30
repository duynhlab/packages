#!/usr/bin/env bash
# scripts/stage-all.sh — produce the Source0 tarball for the mega-RPM.
#
# Layout produced at $BUILD_DIR/staging/:
#   opt/duynhlab/<svc>/{bin,BINARY_VERSION}
#   (migrations are embedded in the service binary — no loose SQL is staged; D24)
#   opt/duynhlab/frontend/dist/...
#   opt/duynhlab/etc/{env-global.properties, manifest}
#   opt/duynhlab/{nginx,valkey,postgresql,secret-tpl,logrotate}/...
#   opt/duynhlab/lib/{init-service.sh, password-generator.sh,
#                     duynhctl, duynhdb, duynhenv,
#                     duynhpass, duynhctl.bash-completion}
#   systemd/duynhlab-*.{service,target}
#
# Final tarball:
#   $BUILD_DIR/sources/duynhlab-${VERSION}-staging.tar.gz   (used as Source0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VERSION="${VERSION:-$(date -u +%Y.%m.%d)}"
PLATFORM_VERSION="$VERSION"  # whole-platform (RPM) version, distinct from per-service
STAGE="$BUILD_DIR/staging"
OPT="$STAGE/opt/duynhlab"
SYSD="$STAGE/systemd"
SRC_DIR="$BUILD_DIR/sources"
TARBALL="$SRC_DIR/duynhlab-${VERSION}-staging.tar.gz"

log_info "VERSION=$VERSION"
log_info "STAGE=$STAGE"

# ── 0. Reset staging ──────────────────────────────────────────────────────────
rm -rf "$STAGE"
mkdir -p "$OPT" "$SYSD" "$SRC_DIR"
mkdir -p "$OPT"/{etc,lib,nginx,valkey,postgresql,secret-tpl,logrotate}

# ── 1. Per-service backends ───────────────────────────────────────────────────
extract_backend() {
  local svc=$1 raw_dir="$BUILD_DIR/$svc/raw"
  local payload="$raw_dir/payload" verf="$raw_dir/VERSION"

  [[ -d "$payload" ]] || die "Missing build/$svc/raw/payload — run scripts/build-local.sh or fetch-releases.sh"
  [[ -f "$verf"    ]] || die "Missing VERSION for $svc"

  local dst="$OPT/$svc"
  mkdir -p "$dst"
  cp -a "$payload/." "$dst/"

  # Migrations are embedded in the service binary (//go:embed) — none are staged.
  printf '%s\n' "$(cat "$verf")" > "$dst/BINARY_VERSION"

  chmod 0755 "$dst/bin"/* 2>/dev/null || :
  log_ok "staged $svc"
}

while read -r svc; do
  type=$(svc_field "$svc" type)
  case "$type" in
    backend) extract_backend "$svc" ;;
    static)  ;;  # handled below
    *)       log_warn "unknown type for $svc: $type" ;;
  esac
done < <(svc_list)

# ── 2. Frontend (static) ──────────────────────────────────────────────────────
fe_payload="$BUILD_DIR/frontend/raw/payload"
[[ -d "$fe_payload/dist" ]] || die "Missing frontend payload — run scripts/build-local.sh frontend"
mkdir -p "$OPT/frontend"
cp -a "$fe_payload/." "$OPT/frontend/"
[[ -f "$OPT/frontend/dist/index.html" ]] || die "frontend/dist/index.html missing after copy"
log_ok "staged frontend"

# ── 3. CLI tools + library scripts ────────────────────────────────────────────
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhctl"           "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhdb"      "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhenv"       "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhpass"  "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhlab-bootstrap"       "$OPT/lib/"
install -m 0644 "$REPO_ROOT/packages/common/scripts/duynhctl.bash-completion" "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/rpm/lib/init-service.sh"               "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/rpm/lib/password-generator.sh"         "$OPT/lib/"
log_ok "staged CLI + lib"
# NOTE: duynhctl no longer parses a registry file — it discovers services from
# the filesystem + /etc/duynhlab/<svc>.env, so the RPM needs no yq dependency.

# ── 4. Config templates ───────────────────────────────────────────────────────
cp -a "$REPO_ROOT/packages/rpm/nginx/."      "$OPT/nginx/"
cp -a "$REPO_ROOT/packages/rpm/valkey/."     "$OPT/valkey/"
cp -a "$REPO_ROOT/packages/rpm/postgresql/." "$OPT/postgresql/"
cp -a "$REPO_ROOT/packages/rpm/secret-tpl/." "$OPT/secret-tpl/"
cp -a "$REPO_ROOT/packages/rpm/logrotate/."  "$OPT/logrotate/"
log_ok "staged config templates"

# ── 5. env-global.properties ──────────────────────────────────────────────────
cat > "$OPT/etc/env-global.properties" <<EOF
# /etc/duynhlab/env-global.properties — system-wide defaults loaded by every
# duynhlab-*.service unit. Edit on the deployed host; not overwritten on upgrade.
DUYNHLAB_VERSION=$PLATFORM_VERSION
LOG_LEVEL=info
ENV=production
DB_HOST=127.0.0.1
DB_PORT=5432
DB_SSLMODE=disable
EOF

# bootstrap.env example — only needed for a REMOTE DB. Same-host PostgreSQL uses
# local peer auth (no file). Operators copy this to /etc/duynhlab/bootstrap.env.
cat > "$OPT/etc/bootstrap.env.example" <<'EOF'
# /etc/duynhlab/bootstrap.env — read by duynhlab-bootstrap.service.
# Only needed when PostgreSQL is on ANOTHER host. For a same-host DB, leave this
# file absent: bootstrap connects via local peer auth as the postgres OS user.
#
# SUPERUSER_DSN=postgresql://postgres:CHANGE_ME@db.example.internal:5432/postgres
EOF
log_ok "staged etc/env-global.properties + bootstrap.env.example"

# ── 5b. Composition manifest ──────────────────────────────────────────────────
# Records exactly which service commits went into this build (audit/rebuild).
# Shipped in the RPM at /opt/duynhlab/etc/manifest; release notes embed it too.
MANIFEST="$OPT/etc/manifest"
{
  echo "# duynhlab platform manifest — version $PLATFORM_VERSION"
  echo "# built_at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while read -r svc; do
    verf="$BUILD_DIR/$svc/raw/VERSION"
    [[ -f "$verf" ]] || die "Missing VERSION for $svc (manifest)"
    printf '%s version=%s type=%s\n' "$svc" "$(cat "$verf")" "$(svc_field "$svc" type)"
  done < <(svc_list)
} > "$MANIFEST"
chmod 0644 "$MANIFEST"
log_ok "staged etc/manifest ($(grep -c '^[^#]' "$MANIFEST") services)"

# ── 6. systemd units ──────────────────────────────────────────────────────────
bash "$SCRIPT_DIR/render-systemd.sh" "$SYSD" >/dev/null

# ── 7. Tarball ────────────────────────────────────────────────────────────────
log_step "creating $TARBALL"
tar -C "$STAGE" -czf "$TARBALL" opt systemd
log_ok "staged tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
