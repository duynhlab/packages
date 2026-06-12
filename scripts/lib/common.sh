#!/usr/bin/env bash
# scripts/lib/common.sh — shared helpers for duynhlab/packages scripts.
# Source from other scripts: . "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# ── Repo paths ────────────────────────────────────────────────────────────────
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$COMMON_LIB_DIR/../.." && pwd)"
SERVICES_YAML="${SERVICES_YAML:-$REPO_ROOT/services.yaml}"
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

# ── services.yaml parser (mikefarah yq v4) ────────────────────────────────────
# BUILD-TIME dependency — runs on the developer machine / CI runner that BUILDS
# the RPM. Do not confuse it with the spec's `Requires: yq`, which only applies
# to CUSTOMER hosts that INSTALL the RPM (it covers duynhctl at runtime and
# does nothing for build machines).
#   CI:  installed by .github/workflows/_build-test.yml (curl from GitHub —
#        Ubuntu's `apt install yq` is the unrelated python-yq, wrong tool).
#   Dev: install once: `go install github.com/mikefarah/yq/v4@latest` or grab
#        the binary from https://github.com/mikefarah/yq/releases.
yq_bin() {
  if command -v yq >/dev/null 2>&1; then
    echo yq
  elif [[ -x "$(go env GOPATH 2>/dev/null)/bin/yq" ]]; then
    echo "$(go env GOPATH)/bin/yq"
  else
    die "yq not found. Install: go install github.com/mikefarah/yq/v4@latest"
  fi
}

# svc_list — print every service name on its own line
svc_list() {
  "$(yq_bin)" '.services[].name' "$SERVICES_YAML"
}

# svc_field <name> <field-path>
#   svc_field auth repo            -> duynhlab/auth-service
#   svc_field auth database.name   -> duynhlab_auth
svc_field() {
  local name=$1 field=$2
  "$(yq_bin)" ".services[] | select(.name==\"$name\") | .${field} // \"\"" "$SERVICES_YAML"
}

# svc_field_list <name> <field-path>  — for array fields, one item per line
svc_field_list() {
  local name=$1 field=$2
  "$(yq_bin)" ".services[] | select(.name==\"$name\") | .${field}[]?" "$SERVICES_YAML"
}

# svc_build_env <name> — print KEY=VALUE lines from .build.env (static services).
#   Used to bake Vite build-time vars (e.g. VITE_API_BASE_URL) before `npm run build`.
svc_build_env() {
  local name=$1
  "$(yq_bin)" -r \
    ".services[] | select(.name==\"$name\") | .build.env // {} | to_entries | .[] | .key + \"=\" + .value" \
    "$SERVICES_YAML"
}

svc_exists() {
  local name=$1
  svc_list | grep -qx "$name"
}

# ── Misc ──────────────────────────────────────────────────────────────────────
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}
