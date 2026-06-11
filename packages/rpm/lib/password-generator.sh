#!/usr/bin/env bash
# password-generator.sh — generate /etc/duynhlab/<svc>.env files.
#
# - Reads templates from /opt/duynhlab/secret-tpl/<svc>.env.tpl
# - Substitutes __DB_PASSWORD__ with a fresh 32-char random string per service
# - Writes /etc/duynhlab/<svc>.env mode 0640 root:duynhlab
# - Idempotent: never overwrites an existing env file
#
# INCREMENTAL VERSIONING:
# /etc/duynhlab/secret_version.properties records the highest version block
# that has completed. %post calls this script on EVERY install AND upgrade;
# blocks below run only when their version is newer than the recorded one,
# so a future release can ADD a new secret without re-initializing old ones.
#
# To add a secret in a future release:
#   1. add an `if [ "$have" -lt N ]; then … fi` block below (N = next number)
#   2. bump CURRENT_SECRET_VERSION to N
# Per-file `[ -f "$env_file" ] && continue` guards stay as a second safety net.
set -eu

ETC=/etc/duynhlab
TPL=/opt/duynhlab/secret-tpl
STATE_FILE="$ETC/secret_version.properties"
CURRENT_SECRET_VERSION=1

GEN_PASS=/opt/duynhlab/lib/duynhlab-gen-password
GEN_ENV=/opt/duynhlab/lib/duynhlab-gen-env

log() { printf '[password-generator] %s\n' "$*"; }

mkdir -p "$ETC"
chmod 0755 "$ETC"

have=0
if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  have="${secretVersion:-0}"
fi

if [ "$have" -ge "$CURRENT_SECRET_VERSION" ]; then
  log "secrets already at version $have; nothing to do"
  exit 0
fi

# ── v1: initial per-service env files (8 backends) ───────────────────────────
if [ "$have" -lt 1 ]; then
  log "applying secret version 1 (initial env generation)"
  for tpl in "$TPL"/*.env.tpl; do
    [ -f "$tpl" ] || continue
    svc=$(basename "$tpl" .env.tpl)
    env_file="$ETC/$svc.env"

    if [ -f "$env_file" ]; then
      log "preserving existing $env_file"
      continue
    fi

    if [ -x "$GEN_ENV" ]; then
      "$GEN_ENV" "$svc"
    else
      # Inline fallback if duynhlab-gen-env is missing.
      pass=$("$GEN_PASS" 32 2>/dev/null || \
             tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 32)
      sed "s/__DB_PASSWORD__/${pass}/g" "$tpl" > "$env_file"
      chown root:duynhlab "$env_file" 2>/dev/null || :
      chmod 0640 "$env_file"
      log "generated $env_file"
    fi
  done
fi

# ── v2, v3, …: future releases add new blocks here (see header) ──────────────

cat > "$STATE_FILE" <<EOF
# Tracks which secret-generation version has completed (see
# password-generator.sh — new releases append numbered blocks there).
secretVersion=$CURRENT_SECRET_VERSION
generatedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chown root:duynhlab "$STATE_FILE" 2>/dev/null || :
chmod 0640 "$STATE_FILE"

log "done (secret version $CURRENT_SECRET_VERSION)"
exit 0
