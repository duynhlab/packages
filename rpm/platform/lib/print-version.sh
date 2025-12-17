#!/bin/bash
# Print and log version information
# Usage: print-version.sh [install|upgrade]

set -euo pipefail

VERSION="%{version}"
LOG_FILE="/var/log/platform/version.log"
INSTALL_TYPE="${1:-install}"

mkdir -p "$(dirname "$LOG_FILE")"

# Log with timestamp
echo "$VERSION installed on $(date +'%Y-%m-%d %H:%M:%S %z')" >> "$LOG_FILE"

# Print to console
if [ "$INSTALL_TYPE" = "upgrade" ]; then
    echo "Platform upgraded to version $VERSION"
else
    echo "Platform version $VERSION installed"
fi

