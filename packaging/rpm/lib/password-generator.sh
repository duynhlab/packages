#!/usr/bin/env bash
# password-generator.sh — generate /etc/duynhlab/<svc>.env on first install.
#
# - Reads templates from /opt/duynhlab/secret-tpl/<svc>.env.tpl
# - Substitutes __DB_PASSWORD__ with a fresh 32-char random string per service
# - Writes /etc/duynhlab/<svc>.env mode 0640 root:duynhlab
# - Idempotent: never overwrites an existing env file
# - Tracks state via /etc/duynhlab/secret_version.properties
set -eu

ETC=/etc/duynhlab
TPL=/opt/duynhlab/secret-tpl
STATE_FILE="$ETC/secret_version.properties"
SECRET_VERSION=1

GEN_PASS=/opt/duynhlab/lib/duynhlab-gen-password
GEN_ENV=/opt/duynhlab/lib/duynhlab-gen-env

log() { printf '[password-generator] %s\n' "$*"; }

mkdir -p "$ETC"
chmod 0755 "$ETC"

if [ -f "$STATE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$STATE_FILE"
  if [ "${secretVersion:-0}" -ge "$SECRET_VERSION" ]; then
    log "secrets already initialized (version=$secretVersion); nothing to do"
    exit 0
  fi
fi

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

cat > "$STATE_FILE" <<EOF
# Tracks which secret-generation version has run.
# Bump SECRET_VERSION in password-generator.sh to force re-init.
secretVersion=$SECRET_VERSION
generatedAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
chmod 0644 "$STATE_FILE"

log "done"
exit 0
