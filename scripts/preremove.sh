#!/bin/bash
# Pre-removal script for Platform package
# Handles service stop and disable before package removal

set -e

# Script parameters:
# $1: Remove action (0=remove, 1=upgrade)
REMOVE_ACTION="${1:-0}"

# Log directory base path
LOG_BASE="/var/log/platform"

# ============================================================================
# Helper Functions
# ============================================================================

# Stop platform services
stop_services() {
    echo "Stopping platform services..."
    if systemctl is-active --quiet platform-all.target 2>/dev/null; then
        systemctl stop platform-all.target 2>/dev/null || true
        echo "  [OK] Platform services stopped"
    else
        echo "  [INFO] Platform services already stopped"
    fi
}

# Disable platform services
disable_services() {
    echo "Disabling platform services..."
    systemctl disable platform-all.target 2>/dev/null || true
    echo "  [OK] Platform services disabled"
}

# Remove log directories
remove_log_directories() {
    echo "Removing log directories..."
    if [ -d "$LOG_BASE" ]; then
        rm -rf "$LOG_BASE"
        echo "  [OK] Log directories removed"
    else
        echo "  [INFO] Log directories not found (already removed)"
    fi
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    # Only perform removal actions (not upgrade)
    if [ "$REMOVE_ACTION" -eq 0 ]; then
        echo "Pre-remove: Package removal detected (action=$REMOVE_ACTION)"
        
        # Stop services
        stop_services
        
        # Disable services
        disable_services
        
        # Remove log directories
        remove_log_directories
        
        echo "Pre-removal completed successfully."
    else
        echo "Pre-remove: Package upgrade detected (action=$REMOVE_ACTION)"
        echo "  No pre-removal actions needed for upgrade"
    fi
}

# Execute main function
main "$@"

