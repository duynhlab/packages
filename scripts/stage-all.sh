#!/usr/bin/env bash
# scripts/stage-all.sh — produce the Source0 tarball for the mega-RPM.
#
# Layout produced at $BUILD_DIR/staging/:
#   opt/duynhlab/<svc>/{bin,BINARY_VERSION,SCHEMA_VERSION}
#   (migrations are embedded in the service binary — no loose SQL is staged; D24)
#   opt/duynhlab/frontend/dist/...
#   opt/duynhlab/etc/{services.yaml, env-global.properties}
#   opt/duynhlab/{nginx,valkey,postgresql,secret-tpl,logrotate}/...
#   opt/duynhlab/lib/{init-service.sh, password-generator.sh,
#                     duynhlab-ctl, duynhlab-db-setup, duynhlab-gen-env,
#                     duynhlab-gen-password, duynhlab-ctl.bash-completion}
#   systemd/duynhlab-*.{service,target}
#
# Final tarball:
#   $BUILD_DIR/sources/duynhlab-${VERSION}-staging.tar.gz   (used as Source0)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VERSION="${VERSION:-$(date -u +%Y.%m.%d)}"
# extract_backend sources each build-info.env, which also defines VERSION —
# capture the platform version up front so later sections don't see the clobber.
PLATFORM_VERSION="$VERSION"
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
  [[ -d "$raw_dir" ]] || die "Missing build/$svc/raw — run scripts/build-local.sh"

  local bin_tgz info
  bin_tgz=$(ls "$raw_dir"/*-linux-amd64.tar.gz 2>/dev/null | head -1)
  info="$raw_dir/build-info.env"

  [[ -f "$bin_tgz" ]] || die "Missing binary tarball for $svc in $raw_dir"
  [[ -f "$info"    ]] || die "Missing build-info.env for $svc"

  local dst="$OPT/$svc"
  mkdir -p "$dst/bin"
  tar -xzf "$bin_tgz" --strip-components=1 -C "$dst"

  # SCHEMA_VERSION (audit-only): highest embedded migration, recorded by
  # build-local.sh into build-info.env. Migrations themselves ship inside the
  # binary (//go:embed) — none are staged here.
  # shellcheck disable=SC1090
  . "$info"
  printf '%s\n' "${VERSION:-unknown}"   > "$dst/BINARY_VERSION"
  printf '%s\n' "${SCHEMA_VERSION:-1}"  > "$dst/SCHEMA_VERSION"

  chmod 0755 "$dst/bin"/* 2>/dev/null || :
  log_ok "staged $svc ($(basename "$bin_tgz"))"
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
frontend_tgz=$(ls "$BUILD_DIR/frontend/raw"/*-dist.tar.gz 2>/dev/null | head -1)
[[ -f "$frontend_tgz" ]] || die "Missing frontend dist tarball"
mkdir -p "$OPT/frontend"
tar -xzf "$frontend_tgz" -C "$OPT/frontend"
[[ -f "$OPT/frontend/dist/index.html" ]] || die "frontend/dist/index.html missing after extract"
log_ok "staged frontend"

# ── 3. CLI tools + library scripts ────────────────────────────────────────────
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhlab-ctl"           "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhlab-db-setup"      "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhlab-gen-env"       "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/common/scripts/duynhlab-gen-password"  "$OPT/lib/"
install -m 0644 "$REPO_ROOT/packages/common/scripts/duynhlab-ctl.bash-completion" "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/rpm/lib/init-service.sh"               "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packages/rpm/lib/password-generator.sh"         "$OPT/lib/"
log_ok "staged CLI + lib"

# ── 4. Config templates ───────────────────────────────────────────────────────
cp -a "$REPO_ROOT/packages/rpm/nginx/."      "$OPT/nginx/"
cp -a "$REPO_ROOT/packages/rpm/valkey/."     "$OPT/valkey/"
cp -a "$REPO_ROOT/packages/rpm/postgresql/." "$OPT/postgresql/"
cp -a "$REPO_ROOT/packages/rpm/secret-tpl/." "$OPT/secret-tpl/"
cp -a "$REPO_ROOT/packages/rpm/logrotate/."  "$OPT/logrotate/"
log_ok "staged config templates"

# ── 5. services.yaml + env-global.properties ──────────────────────────────────
install -m 0644 "$REPO_ROOT/services.yaml" "$OPT/etc/services.yaml"

cat > "$OPT/etc/env-global.properties" <<EOF
# /etc/duynhlab/env-global.properties — system-wide defaults loaded by every
# duynhlab-*.service unit. Edit on the deployed host; not overwritten on upgrade.
DUYNHLAB_VERSION=$PLATFORM_VERSION
LOG_LEVEL=info
ENV=production
DB_HOST=127.0.0.1
DB_PORT=5432
DB_SSLMODE=disable
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF
log_ok "staged etc/services.yaml + env-global.properties"

# ── 5b. Composition manifest ──────────────────────────────────────────────────
# Records exactly which service commits went into this build (audit/rebuild).
# Shipped in the RPM at /opt/duynhlab/etc/manifest; release notes embed it too.
MANIFEST="$OPT/etc/manifest"
{
  echo "# duynhlab platform manifest — version $PLATFORM_VERSION"
  echo "# built_at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  while read -r svc; do
    info="$BUILD_DIR/$svc/raw/build-info.env"
    [[ -f "$info" ]] || die "Missing build-info.env for $svc (manifest)"
    # Subshell: build-info.env sets VERSION/GIT_SHA — don't clobber our globals.
    ( . "$info"; printf '%s sha=%s type=%s\n' "$svc" "${GIT_SHA:-unknown}" "${TYPE:-unknown}" )
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
