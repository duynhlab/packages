#!/bin/sh
# common-preinstall — ensure duynhlab user/group exist before any per-service RPM.
set -e
if ! getent group duynhlab >/dev/null; then
  groupadd --system duynhlab
fi
if ! getent passwd duynhlab >/dev/null; then
  useradd --system --gid duynhlab --home-dir /opt/duynhlab \
    --shell /sbin/nologin --comment "duynhlab platform" duynhlab
fi
mkdir -p /opt/duynhlab /etc/duynhlab/common
exit 0
