#!/bin/sh
# frontend-postremove — reload nginx after vhost removal.
set -e
if [ "$1" = "0" ] || [ "$1" = "remove" ]; then
  if command -v nginx >/dev/null 2>&1 && systemctl is-active --quiet nginx; then
    systemctl reload nginx >/dev/null 2>&1 || :
  fi
fi
exit 0
