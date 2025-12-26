#!/bin/bash
# Post-removal script for Platform package
# Handles systemd daemon reload after package removal

set -e

# Script parameters:
# $1: Remove action (0=remove, 1=upgrade)
REMOVE_ACTION="${1:-0}"

# ============================================================================
# Helper Functions
# ============================================================================

# Reload systemd daemon
reload_systemd() {
    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    echo "  [OK] Systemd daemon reloaded"
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    # Reload systemd for both removal and upgrade
    reload_systemd
    
    if [ "$REMOVE_ACTION" -eq 0 ]; then
        echo "Post-remove: Package removal completed"
        echo "Platform removed successfully"
    else
        echo "Post-remove: Package upgrade completed"
    fi
}

# Execute main function
main "$@"

