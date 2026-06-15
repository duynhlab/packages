#!/usr/bin/env bash
# scripts/render-systemd.sh — render systemd unit + target files from the
# hardcoded service registry (scripts/lib/common.sh)
# Output goes into build/systemd/<svc>.service and build/systemd/duynhlab-platform.target
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

TPL_DIR="$REPO_ROOT/packages/rpm/systemd"
OUT_DIR="${1:-$BUILD_DIR/systemd}"
mkdir -p "$OUT_DIR"

UNIT_TPL="$TPL_DIR/duynhlab-service.tmpl.service"
TARGET_TPL="$TPL_DIR/duynhlab-platform.target.tmpl"

# ── Render per-service .service files ─────────────────────────────────────────
WANTS=""
while read -r svc; do
  type=$(svc_field "$svc" type)
  [[ "$type" == "static" ]] && { log_warn "skip systemd for static service: $svc"; continue; }

  binary=$(svc_field "$svc" binary)
  after_list=$(svc_field_list "$svc" dependencies.after | sed 's/^/ /' | tr -d '\n')
  env_lines=""
  while read -r env_path; do
    [[ -z "$env_path" ]] && continue
    env_lines+="EnvironmentFile=-${env_path}"$'\n'
  done < <(svc_field_list "$svc" dependencies.env_files)

  SERVICE_NAME="$svc" \
  BINARY_NAME="$binary" \
  EXTRA_AFTER="$after_list" \
  EXTRA_ENV_FILES="$env_lines" \
    envsubst '$SERVICE_NAME $BINARY_NAME $EXTRA_AFTER $EXTRA_ENV_FILES' \
    < "$UNIT_TPL" > "$OUT_DIR/duynhlab-$svc.service"

  WANTS+="Wants=duynhlab-$svc.service"$'\n'
  log_ok "rendered duynhlab-$svc.service"
done < <(svc_list)

# ── Render duynhlab-platform.target ───────────────────────────────────────────
WANTS_LINES="$WANTS" envsubst '$WANTS_LINES' \
  < "$TARGET_TPL" > "$OUT_DIR/duynhlab-platform.target"
log_ok "rendered duynhlab-platform.target ($(grep -c '^Wants=duynhlab-' "$OUT_DIR/duynhlab-platform.target") services)"

# ── Copy static units (infra target + one-time bootstrap) ─────────────────────
install -m 0644 "$TPL_DIR/duynhlab-infra.target" "$OUT_DIR/duynhlab-infra.target"
log_ok "copied duynhlab-infra.target"
install -m 0644 "$TPL_DIR/duynhlab-bootstrap.service" "$OUT_DIR/duynhlab-bootstrap.service"
log_ok "copied duynhlab-bootstrap.service"

log_info "Output: ${OUT_DIR#$REPO_ROOT/}"
