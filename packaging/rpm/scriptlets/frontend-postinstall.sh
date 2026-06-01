#!/bin/sh
# frontend-postinstall — reload nginx if running, validate config.
set -e

if command -v nginx >/dev/null 2>&1; then
  if nginx -t >/dev/null 2>&1; then
    if systemctl is-active --quiet nginx; then
      systemctl reload nginx >/dev/null 2>&1 || :
    fi
  else
    echo "WARN: nginx -t failed; review /etc/nginx/conf.d/duynhlab-frontend.conf" >&2
  fi
fi

echo ""
echo "================================================================"
echo "  duynhlab-frontend installed."
echo "  Static SPA: /opt/duynhlab/frontend/dist"
echo "  vhost:      /etc/nginx/conf.d/duynhlab-frontend.conf"
echo ""
echo "  Enable nginx if needed: systemctl enable --now nginx"
echo "================================================================"

exit 0
