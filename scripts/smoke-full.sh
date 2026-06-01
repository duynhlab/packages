#!/usr/bin/env bash
# scripts/smoke-full.sh — full-systemd smoke test (Phase 2.2).
#
# Spins up:
#   * 1 podman pod (default) with a Postgres 16 sidecar
#   * 1 systemd-enabled Rocky 9 container ("app")
#
# In the app container we:
#   1. install epel + nginx + valkey + postgresql client
#   2. dnf localinstall the mega-RPM
#   3. duynhlab-db-setup <svc> bootstrap   (loop services with DB)
#   4. duynhlab-db-setup <svc> migrate
#   5. systemctl start duynhlab-platform.target
#   6. curl localhost:<port>/health for every backend
#   7. duynhlab-ctl status / logs sanity
#   8. shutdown
#
# Requires: podman with cgroup v2 + `--systemd=true` support (default on
# modern Fedora/Ubuntu/RHEL). On GitHub Actions Ubuntu runners install
# `podman` then run with `--privileged --systemd=always`.
#
# Env knobs:
#   POSTGRES_IMAGE      docker.io/postgres:16-alpine
#   APP_IMAGE           quay.io/centos/centos:stream9
#   POSTGRES_PASSWORD   randomly generated if unset
#   POD_NAME            duynhlab-smoke
#   KEEP_POD=1          don't tear down on exit (debug)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

require_cmd podman

POSTGRES_IMAGE="${POSTGRES_IMAGE:-docker.io/postgres:16-alpine}"
APP_IMAGE="${APP_IMAGE:-quay.io/centos/centos:stream9}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | head -c 24)}"
POD_NAME="${POD_NAME:-duynhlab-smoke}"
APP_NAME="$POD_NAME-app"
DB_NAME_C="$POD_NAME-db"

BACKENDS=(auth user product cart order review notification shipping)
declare -A PORTS=(
  [auth]=8001 [user]=8002 [product]=8003 [cart]=8004
  [order]=8005 [review]=8006 [notification]=8007 [shipping]=8008
)

ls "$DIST_DIR"/duynhlab-*.x86_64.rpm >/dev/null 2>&1 \
  || die "No mega-RPM in $DIST_DIR — run scripts/build-rpm.sh"

cleanup() {
  local rc=$?
  if [[ -z "${KEEP_POD:-}" ]]; then
    log_step "cleanup pod $POD_NAME"
    podman rm -f "$APP_NAME" "$DB_NAME_C" >/dev/null 2>&1 || :
    podman pod rm -f "$POD_NAME" >/dev/null 2>&1 || :
  else
    log_warn "KEEP_POD=1 — leaving pod $POD_NAME running"
  fi
  exit "$rc"
}
trap cleanup EXIT INT TERM

# Always start clean.
podman rm -f "$APP_NAME" "$DB_NAME_C" >/dev/null 2>&1 || :
podman pod rm -f "$POD_NAME"          >/dev/null 2>&1 || :

log_step "create pod $POD_NAME (publish 8001-8008)"
publish_args=()
for p in 8001 8002 8003 8004 8005 8006 8007 8008; do
  publish_args+=(-p "$p:$p")
done
podman pod create --name "$POD_NAME" "${publish_args[@]}" >/dev/null

# ── 1. Postgres sidecar ───────────────────────────────────────────────────────
log_step "start postgres ($POSTGRES_IMAGE)"
podman run -d \
  --pod "$POD_NAME" --name "$DB_NAME_C" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB=postgres \
  "$POSTGRES_IMAGE" >/dev/null

log_info "waiting for postgres to accept connections"
for i in $(seq 1 30); do
  if podman exec "$DB_NAME_C" pg_isready -U postgres >/dev/null 2>&1; then
    log_ok "postgres ready (after ${i}s)"
    break
  fi
  sleep 1
  [[ $i == 30 ]] && die "Postgres did not become ready in 30s"
done

# ── 2. App container (real systemd) ───────────────────────────────────────────
log_step "start app container $APP_NAME (systemd, $APP_IMAGE)"
podman run -d \
  --pod "$POD_NAME" --name "$APP_NAME" \
  --systemd=always \
  --cap-add=SYS_ADMIN \
  --tmpfs /tmp --tmpfs /run --tmpfs /run/lock \
  -v "$REPO_ROOT/dist:/srv/dist:ro" \
  "$APP_IMAGE" \
  /sbin/init >/dev/null

log_info "waiting for systemd inside container"
for i in $(seq 1 30); do
  if podman exec "$APP_NAME" systemctl is-system-running >/dev/null 2>&1 \
     || podman exec "$APP_NAME" systemctl is-system-running 2>/dev/null \
        | grep -qE '^(running|degraded|starting)$'; then
    log_ok "systemd up (after ${i}s)"
    break
  fi
  sleep 1
  [[ $i == 30 ]] && die "systemd did not start in 30s"
done

exec_app() {
  podman exec "$APP_NAME" bash -c "$1"
}

# ── 3. Install dependencies + mega-RPM ────────────────────────────────────────
log_step "install dependencies + mega-RPM"
exec_app '
  set -e
  dnf -y install epel-release >/dev/null
  dnf -y module enable postgresql:16 >/dev/null
  dnf -y install nginx valkey postgresql shadow-utils which file curl >/dev/null
  dnf -y localinstall /srv/dist/duynhlab-*.x86_64.rpm
'
log_ok "RPM installed"

# ── 4. Point env files at the postgres sidecar (same pod = localhost) ────────
log_step "rewrite env-global.properties to talk to sidecar postgres"
exec_app '
  install -m 0644 /etc/duynhlab/env-global.properties /etc/duynhlab/env-global.properties.bak
  cat > /etc/duynhlab/env-global.properties <<EOF
DUYNHLAB_VERSION=smoke
LOG_LEVEL=info
ENV=test
DB_HOST=127.0.0.1
DB_PORT=5432
DB_SSLMODE=disable
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
EOF
'

# ── 5. Bootstrap + migrate every backend DB ───────────────────────────────────
log_step "bootstrap + migrate per-service databases"
for svc in "${BACKENDS[@]}"; do
  exec_app "
    set -e
    SUPERUSER_DSN='postgresql://postgres:${POSTGRES_PASSWORD}@127.0.0.1:5432/postgres?sslmode=disable' \
      duynhlab-db-setup bootstrap $svc
    duynhlab-db-setup migrate $svc
    duynhlab-db-setup status   $svc
  "
done
log_ok "DB bootstrap + migrate OK"

# ── 6. Start platform target + assert health ─────────────────────────────────
log_step "systemctl enable --now duynhlab-platform.target"
exec_app 'systemctl daemon-reload && systemctl enable --now duynhlab-platform.target'

log_info "wait 5s for services to settle"
sleep 5

failed=()
for svc in "${BACKENDS[@]}"; do
  port="${PORTS[$svc]}"
  state=$(exec_app "systemctl is-active duynhlab-$svc.service" || true)
  if [[ "$state" != "active" ]]; then
    log_error "duynhlab-$svc is $state"
    exec_app "journalctl -u duynhlab-$svc --no-pager -n 50" || :
    failed+=("$svc")
    continue
  fi
  if ! exec_app "curl -fsS --max-time 3 http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    log_error "health check failed for duynhlab-$svc on :$port"
    exec_app "journalctl -u duynhlab-$svc --no-pager -n 30" || :
    failed+=("$svc")
  else
    log_ok "duynhlab-$svc active + /health 200"
  fi
done

# ── 7. duynhlab-ctl sanity ────────────────────────────────────────────────────
log_step "duynhlab-ctl status / ports"
exec_app 'duynhlab-ctl status || true; echo ; duynhlab-ctl ports || true'

# ── 8. Clean shutdown ─────────────────────────────────────────────────────────
log_step "systemctl stop duynhlab-platform.target"
exec_app 'systemctl stop duynhlab-platform.target'

if [[ ${#failed[@]} -gt 0 ]]; then
  die "Failed services: ${failed[*]}"
fi

echo ""
echo "================================================================"
echo "  FULL SMOKE TEST PASSED — all backends healthy on real systemd"
echo "================================================================"
