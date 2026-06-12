#!/bin/sh
set -e
systemctl daemon-reload >/dev/null 2>&1 || :
echo "duynhlab-common installed. Run 'duynhctl list' to see services."
exit 0
