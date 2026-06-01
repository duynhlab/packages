#!/bin/sh
set -e
systemctl daemon-reload >/dev/null 2>&1 || :
echo "duynhlab-common installed. Run 'duynhlab-ctl list' to see services."
exit 0
