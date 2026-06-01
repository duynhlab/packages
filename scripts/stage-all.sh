#!/usr/bin/env bash
# scripts/stage-all.sh — produce the Source0 tarball for the mega-RPM.
#
# Layout produced at $BUILD_DIR/staging/:
#   opt/duynhlab/<svc>/{bin,migrations/sql,BINARY_VERSION,SCHEMA_VERSION}
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

  local bin_tgz mig_tgz info
  bin_tgz=$(ls "$raw_dir"/*-linux-amd64.tar.gz 2>/dev/null | head -1)
  mig_tgz=$(ls "$raw_dir"/*-migrations.tar.gz   2>/dev/null | head -1)
  info="$raw_dir/build-info.env"

  [[ -f "$bin_tgz" ]] || die "Missing binary tarball for $svc in $raw_dir"
  [[ -f "$info"    ]] || die "Missing build-info.env for $svc"

  local dst="$OPT/$svc"
  mkdir -p "$dst/bin" "$dst/migrations"
  tar -xzf "$bin_tgz" --strip-components=1 -C "$dst"
  if [[ -n "$mig_tgz" && -f "$mig_tgz" ]]; then
    tar -xzf "$mig_tgz" -C "$dst/migrations"
  fi

  # shellcheck disable=SC1090
  . "$info"
  printf '%s\n' "${VERSION:-unknown}"        > "$dst/BINARY_VERSION"
  local schema=1
  if [[ -d "$dst/migrations/sql" ]]; then
    schema=$(ls "$dst/migrations/sql"/*.sql 2>/dev/null | wc -l)
  fi
  printf '%s\n' "$schema" > "$dst/SCHEMA_VERSION"

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
install -m 0755 "$REPO_ROOT/packaging/common/scripts/duynhlab-ctl"           "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packaging/common/scripts/duynhlab-db-setup"      "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packaging/common/scripts/duynhlab-gen-env"       "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packaging/common/scripts/duynhlab-gen-password"  "$OPT/lib/"
install -m 0644 "$REPO_ROOT/packaging/common/scripts/duynhlab-ctl.bash-completion" "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packaging/rpm/lib/init-service.sh"               "$OPT/lib/"
install -m 0755 "$REPO_ROOT/packaging/rpm/lib/password-generator.sh"         "$OPT/lib/"
log_ok "staged CLI + lib"

# ── 4. golang-migrate binary as duynhlab-db-migrate ───────────────────────────
MIGRATE_BIN="$OPT/lib/duynhlab-db-migrate"
if [[ ! -x "$MIGRATE_BIN" ]]; then
  if [[ -n "${SKIP_MIGRATE_DOWNLOAD:-}" ]]; then
    log_warn "SKIP_MIGRATE_DOWNLOAD set — installing stub for duynhlab-db-migrate"
    cat > "$MIGRATE_BIN" <<'EOF'
#!/usr/bin/env bash
echo "duynhlab-db-migrate stub — real binary not installed" >&2
exit 1
EOF
    chmod 0755 "$MIGRATE_BIN"
  else
    MIGRATE_VER="${MIGRATE_VER:-v4.17.0}"
    URL="https://github.com/golang-migrate/migrate/releases/download/${MIGRATE_VER}/migrate.linux-amd64.tar.gz"
    log_info "downloading golang-migrate $MIGRATE_VER"
    tmp=$(mktemp -d)
    if command -v curl >/dev/null; then
      curl -fsSL -o "$tmp/m.tgz" "$URL"
    else
      die "curl required to download golang-migrate (or set SKIP_MIGRATE_DOWNLOAD=1)"
    fi
    tar -xzf "$tmp/m.tgz" -C "$tmp"
    install -m 0755 "$tmp/migrate" "$MIGRATE_BIN"
    rm -rf "$tmp"
    log_ok "installed duynhlab-db-migrate ($MIGRATE_VER)"
  fi
fi

# ── 5. Config templates ───────────────────────────────────────────────────────
cp -a "$REPO_ROOT/packaging/rpm/nginx/."      "$OPT/nginx/"
cp -a "$REPO_ROOT/packaging/rpm/valkey/."     "$OPT/valkey/"
cp -a "$REPO_ROOT/packaging/rpm/postgresql/." "$OPT/postgresql/"
cp -a "$REPO_ROOT/packaging/rpm/secret-tpl/." "$OPT/secret-tpl/"
cp -a "$REPO_ROOT/packaging/rpm/logrotate/."  "$OPT/logrotate/"
log_ok "staged config templates"

# ── 6. services.yaml + env-global.properties ──────────────────────────────────
install -m 0644 "$REPO_ROOT/services.yaml" "$OPT/etc/services.yaml"

cat > "$OPT/etc/env-global.properties" <<EOF
# /etc/duynhlab/env-global.properties — system-wide defaults loaded by every
# duynhlab-*.service unit. Edit on the deployed host; not overwritten on upgrade.
DUYNHLAB_VERSION=$VERSION
LOG_LEVEL=info
ENV=production
DB_HOST=127.0.0.1
DB_PORT=5432
DB_SSLMODE=disable
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF
log_ok "staged etc/services.yaml + env-global.properties"

# ── 7. systemd units ──────────────────────────────────────────────────────────
bash "$SCRIPT_DIR/render-systemd.sh" "$SYSD" >/dev/null

# ── 8. Tarball ────────────────────────────────────────────────────────────────
log_step "creating $TARBALL"
tar -C "$STAGE" -czf "$TARBALL" opt systemd
log_ok "staged tarball: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
