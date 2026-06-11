#!/usr/bin/env bash
# init-service.sh — idempotent migrator run from %post.
#
# - Creates /var/log/duynhlab/<svc>/ for every backend.
# - Drops template configs from /opt/duynhlab/etc/ -> /etc/duynhlab/
# - Drops nginx vhost from /opt/duynhlab/nginx/ -> /etc/nginx/conf.d/
# - Drops valkey snippet                       -> /etc/valkey/conf.d/
# - Drops postgres tuning snippet              -> /etc/postgresql/conf.d/  (if exists)
# - Drops logrotate snippets                   -> /etc/logrotate.d/
# - Fixes binary executable bits.
# - Never overwrites files that already exist on the system.
set -euo pipefail

PREFIX=/opt/duynhlab
ETC=/etc/duynhlab
LOG=/var/log/duynhlab
STATE=/var/lib/duynhlab

BACKENDS=(auth user product cart order review notification shipping)

log()  { printf '[init-service] %s\n' "$*"; }

# ── 1. Log + state directories ───────────────────────────────────────────────
install -d -m 0755 -o duynhlab -g duynhlab "$LOG"
install -d -m 0750 -o duynhlab -g duynhlab "$STATE"
for svc in "${BACKENDS[@]}"; do
  install -d -m 0755 -o duynhlab -g duynhlab "$LOG/$svc"
done
install -d -m 0755 -o root -g root "$LOG/nginx"

# ── 2. /etc/duynhlab/ — global config + services.yaml ────────────────────────
install -d -m 0755 -o root -g duynhlab "$ETC"

copy_if_missing() {
  local src=$1 dst=$2 mode=$3 owner=$4
  if [ -f "$src" ] && [ ! -f "$dst" ]; then
    install -Dm "$mode" -o "${owner%:*}" -g "${owner#*:}" "$src" "$dst"
    log "installed $dst"
  fi
}

copy_if_missing "$PREFIX/etc/services.yaml"          "$ETC/services.yaml"          0644 root:root
copy_if_missing "$PREFIX/etc/env-global.properties"  "$ETC/env-global.properties"  0644 root:root

# ── 3. nginx vhost ───────────────────────────────────────────────────────────
if [ -d /etc/nginx/conf.d ]; then
  copy_if_missing "$PREFIX/nginx/duynhlab.conf" \
                  /etc/nginx/conf.d/duynhlab.conf \
                  0644 root:root
fi

# ── 4. valkey snippet (best-effort — package may not be installed) ───────────
for valkey_dir in /etc/valkey/conf.d /etc/valkey; do
  if [ -d "$valkey_dir" ]; then
    copy_if_missing "$PREFIX/valkey/duynhlab.conf" \
                    "$valkey_dir/duynhlab.conf" \
                    0640 root:root
    break
  fi
done

# ── 5. postgresql tuning (best-effort) ───────────────────────────────────────
for pg_dir in /etc/postgresql/conf.d \
              /var/lib/pgsql/data/conf.d \
              /var/lib/pgsql/16/data/conf.d \
              /var/lib/pgsql/15/data/conf.d \
              /var/lib/pgsql/14/data/conf.d; do
  if [ -d "$pg_dir" ]; then
    copy_if_missing "$PREFIX/postgresql/duynhlab-tuning.conf" \
                    "$pg_dir/duynhlab-tuning.conf" \
                    0644 postgres:postgres
    break
  fi
done

# ── 6. logrotate ─────────────────────────────────────────────────────────────
if [ -d /etc/logrotate.d ]; then
  for f in "$PREFIX"/logrotate/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    copy_if_missing "$f" "/etc/logrotate.d/$name" 0644 root:root
  done
fi

# ── 7. Binary executable bits (in case tar lost them) ────────────────────────
chmod 0755 "$PREFIX"/lib/*.sh 2>/dev/null || :
chmod 0755 "$PREFIX"/lib/duynhlab-* 2>/dev/null || :
for svc in "${BACKENDS[@]}"; do
  bin="$PREFIX/$svc/bin/${svc}-service"
  if [ -f "$bin" ]; then
    chmod 0755 "$bin"
    chown duynhlab:duynhlab "$bin"
  fi
done

systemctl daemon-reload >/dev/null 2>&1 || :

log "init-service complete"
exit 0
