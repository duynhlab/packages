#!/bin/sh
# preinstall — create duynhlab system user and group if missing
set -e

if ! getent group duynhlab >/dev/null; then
  groupadd --system duynhlab
fi
if ! getent passwd duynhlab >/dev/null; then
  useradd --system --gid duynhlab --home-dir /opt/duynhlab \
    --shell /sbin/nologin --comment "duynhlab platform" duynhlab
fi

exit 0
