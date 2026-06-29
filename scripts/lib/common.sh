#!/usr/bin/env bash
# scripts/lib/common.sh — shared helpers for duynhlab/packages scripts.
# Source from other scripts: . "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# ── Repo paths ────────────────────────────────────────────────────────────────
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$COMMON_LIB_DIR/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
DUYNHLAB_SRC_ROOT="${DUYNHLAB_SRC_ROOT:-$(cd "$REPO_ROOT/.." && pwd)}"

# ── Logging ───────────────────────────────────────────────────────────────────
if [[ -t 2 ]]; then
  _C_RED=$'\033[31m'; _C_GRN=$'\033[32m'; _C_YEL=$'\033[33m'
  _C_BLU=$'\033[34m'; _C_DIM=$'\033[2m'; _C_RST=$'\033[0m'
else
  _C_RED=; _C_GRN=; _C_YEL=; _C_BLU=; _C_DIM=; _C_RST=
fi

log_info()  { printf "%s[INFO]%s  %s\n"  "$_C_BLU" "$_C_RST" "$*" >&2; }
log_ok()    { printf "%s[OK]%s    %s\n"  "$_C_GRN" "$_C_RST" "$*" >&2; }
log_warn()  { printf "%s[WARN]%s  %s\n"  "$_C_YEL" "$_C_RST" "$*" >&2; }
log_error() { printf "%s[ERROR]%s %s\n"  "$_C_RED" "$_C_RST" "$*" >&2; }
log_step()  { printf "%s──▶%s %s\n"      "$_C_DIM" "$_C_RST" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# ── Dependency checks ─────────────────────────────────────────────────────────
require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Required command not found: $c"
  done
}

# pick_runner <host-cmd> [override] — echo how to run a tool that may be absent
# on the host: "host" if <host-cmd> exists, else "docker", else die. An explicit
# non-empty <override> is honored verbatim. Shared by build-rpm.sh (rpmbuild)
# and publish-yum-repo.sh (createrepo_c).
pick_runner() {
  local hostcmd=$1 override=${2:-}
  if [[ -n "$override" ]]; then printf '%s\n' "$override"; return; fi
  if command -v "$hostcmd" >/dev/null 2>&1; then echo host
  elif command -v docker   >/dev/null 2>&1; then echo docker
  else die "No $hostcmd on host and no docker available"; fi
}

# ── Service registry (hardcoded — single source of truth) ─────────────────────
# Was parsed from services.yaml via yq; inlined here so the build needs no yq and
# the RPM ships no registry file. Adding/removing a service = edit THIS block +
# packages/rpm/secret-tpl/<svc>.env.tpl + packages/rpm/nginx/duynhlab.conf, plus
# the hardcoded service loops in the spec/init-service.sh (see docs/006-add-service.md).
#
# Scalar fields are keyed "<name>|<field>" (only existing keys are set; a missing
# key reads back as ""). svc_list prints names in _SVC_ORDER order.
_SVC_ORDER=(auth user product cart order review notification shipping frontend)

declare -A _SVC=(
  [auth|repo]=duynhlab/auth-service  [auth|src_dir]=auth-service  [auth|binary]=auth-service  [auth|build_path]=./cmd  [auth|port]=8001  [auth|grpc_port]=9001  [auth|type]=backend  [auth|database.name]=duynhlab_auth  [auth|database.app_user]=duynhlab_auth_app  [auth|database.migrator_user]=duynhlab_auth_migrator
  [user|repo]=duynhlab/user-service  [user|src_dir]=user-service  [user|binary]=user-service  [user|build_path]=./cmd  [user|port]=8002  [user|type]=backend  [user|database.name]=duynhlab_user  [user|database.app_user]=duynhlab_user_app  [user|database.migrator_user]=duynhlab_user_migrator
  [product|repo]=duynhlab/product-service  [product|src_dir]=product-service  [product|binary]=product-service  [product|build_path]=./cmd  [product|port]=8003  [product|type]=backend  [product|database.name]=duynhlab_product  [product|database.app_user]=duynhlab_product_app  [product|database.migrator_user]=duynhlab_product_migrator
  [cart|repo]=duynhlab/cart-service  [cart|src_dir]=cart-service  [cart|binary]=cart-service  [cart|build_path]=./cmd  [cart|port]=8004  [cart|type]=backend  [cart|database.name]=duynhlab_cart  [cart|database.app_user]=duynhlab_cart_app  [cart|database.migrator_user]=duynhlab_cart_migrator
  [order|repo]=duynhlab/order-service  [order|src_dir]=order-service  [order|binary]=order-service  [order|build_path]=./cmd  [order|port]=8005  [order|type]=backend  [order|database.name]=duynhlab_order  [order|database.app_user]=duynhlab_order_app  [order|database.migrator_user]=duynhlab_order_migrator
  [review|repo]=duynhlab/review-service  [review|src_dir]=review-service  [review|binary]=review-service  [review|build_path]=./cmd  [review|port]=8006  [review|grpc_port]=9006  [review|type]=backend  [review|database.name]=duynhlab_review  [review|database.app_user]=duynhlab_review_app  [review|database.migrator_user]=duynhlab_review_migrator
  [notification|repo]=duynhlab/notification-service  [notification|src_dir]=notification-service  [notification|binary]=notification-service  [notification|build_path]=./cmd  [notification|port]=8007  [notification|grpc_port]=9007  [notification|type]=backend  [notification|database.name]=duynhlab_notification  [notification|database.app_user]=duynhlab_notification_app  [notification|database.migrator_user]=duynhlab_notification_migrator
  [shipping|repo]=duynhlab/shipping-service  [shipping|src_dir]=shipping-service  [shipping|binary]=shipping-service  [shipping|build_path]=./cmd  [shipping|port]=8008  [shipping|grpc_port]=9008  [shipping|type]=backend  [shipping|database.name]=duynhlab_shipping  [shipping|database.app_user]=duynhlab_shipping_app  [shipping|database.migrator_user]=duynhlab_shipping_migrator
  [frontend|repo]=duynhlab/frontend  [frontend|src_dir]=frontend  [frontend|binary]=  [frontend|build_path]=  [frontend|port]=8080  [frontend|type]=static
)

# Array field dependencies.after (space-separated). Only set where non-empty.
declare -A _SVC_AFTER=(
  [frontend]="nginx.service"
)

# build.env for static services (KEY=VALUE lines) — baked into the SPA at build time.
# VITE_API_BASE_URL is intentionally EMPTY: on the RPM the SPA and the APIs share
# one origin behind local nginx (the gateway role), so the SPA calls relative
# /{service}/v1/... paths — no Kong, no cross-origin. (Empty is honored by the
# frontend's getApiBaseUrl via `??`; cloud builds leave it unset for the gateway.)
declare -A _SVC_BUILDENV=(
  [frontend]=$'VITE_API_BASE_URL=\nVITE_USE_MOCK=false'
)

# svc_list — print every service name on its own line (registry order).
svc_list() { printf '%s\n' "${_SVC_ORDER[@]}"; }

# svc_field <name> <field-path>
#   svc_field auth repo            -> duynhlab/auth-service
#   svc_field auth database.name   -> duynhlab_auth
svc_field() {
  local name=$1 field=$2
  printf '%s\n' "${_SVC[$name|$field]:-}"
}

# svc_field_list <name> <field-path> — for array fields, one item per line.
# Always returns 0 (an empty list is not an error) so callers under
# `set -e`/pipefail don't abort, matching the old `yq '...[]?'` behaviour.
svc_field_list() {
  local name=$1 field=$2
  if [[ "$field" == "dependencies.after" ]]; then
    local v=${_SVC_AFTER[$name]:-}
    [[ -n $v ]] && printf '%s\n' $v     # unquoted: split into one line each
  fi
  return 0
}

# svc_build_env <name> — print KEY=VALUE lines from .build.env (static services).
#   Used to bake Vite build-time vars (e.g. VITE_API_BASE_URL) before `npm run build`.
svc_build_env() {
  local name=$1
  [[ -n "${_SVC_BUILDENV[$name]:-}" ]] && printf '%s\n' "${_SVC_BUILDENV[$name]}"
  return 0
}

svc_exists() {
  local name=$1
  svc_list | grep -qx "$name"
}
