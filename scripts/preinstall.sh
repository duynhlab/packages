#!/bin/bash
# Pre-installation script for Platform package
# Handles port availability checks, log directory creation, and upgrade detection

set -e

# Script parameters:
# $1: Install action
#   RPM: 1=install, 2=upgrade, 0=remove
#   DEB: "install", "upgrade", "remove", "abort-install", "abort-upgrade", "abort-remove"
INSTALL_ACTION="${1:-1}"

# Normalize install action to numeric format for comparison
# DEB uses strings, RPM uses numbers
if [ "$INSTALL_ACTION" = "install" ] || [ "$INSTALL_ACTION" = "abort-install" ]; then
    INSTALL_ACTION_NUM=1
elif [ "$INSTALL_ACTION" = "upgrade" ] || [ "$INSTALL_ACTION" = "abort-upgrade" ]; then
    INSTALL_ACTION_NUM=2
elif [ "$INSTALL_ACTION" = "remove" ] || [ "$INSTALL_ACTION" = "abort-remove" ]; then
    INSTALL_ACTION_NUM=0
else
    # Assume it's already numeric (RPM format)
    INSTALL_ACTION_NUM="$INSTALL_ACTION"
fi

# Ports required by platform services
# Format: single ports or ranges (start-end)
# - Single ports: 
#   - 80 (nginx)
#   - 5672, 5671 (RabbitMQ)
#   - 6379 (Redis)
# - Port ranges:
#   - 8000-8088: All API services (api-server, user-api, checkout-api, voter-api, and any future API services)
#     All API services share this range - no need to specify individual ports per service
REQUIRED_PORTS=("80" "5672" "5671" "6379" "8000-8088")

# Log directory base path
LOG_BASE="/var/log/platform"

# Service user/group
SERVICE_USER="nobody"
SERVICE_GROUP="nobody"

# ============================================================================
# Helper Functions
# ============================================================================

# Check if a port is in use
check_port() {
    local port=$1
    if command -v ss >/dev/null 2>&1; then
        ss -tuln | grep -q ":$port " && return 0 || return 1
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln | grep -q ":$port " && return 0 || return 1
    else
        echo "[WARNING] Neither 'ss' nor 'netstat' found. Cannot check port $port." >&2
        return 1
    fi
}


# Check all required ports (single ports and ranges)
check_all_ports() {
    local all_conflicts=()
    local port_spec
    
    for port_spec in "${REQUIRED_PORTS[@]}"; do
        # Check if it's a range (contains '-')
        if [[ "$port_spec" == *"-"* ]]; then
            # It's a range - check each port in range
            local start_port end_port
            
            # Parse range
            if [[ "$port_spec" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start_port="${BASH_REMATCH[1]}"
                end_port="${BASH_REMATCH[2]}"
                
                # Validate range (start < end)
                if [ "$start_port" -ge "$end_port" ]; then
                    echo "[ERROR] Invalid port range: $port_spec (start port must be less than end port)" >&2
                    return 2
                fi
                
                # Check each port in range
                for ((port=start_port; port<=end_port; port++)); do
                    if check_port "$port"; then
                        all_conflicts+=("$port")
                    fi
                done
            else
                echo "[ERROR] Invalid port range format: $port_spec (expected: start-end)" >&2
                return 2
            fi
        else
            # It's a single port
            if check_port "$port_spec"; then
                all_conflicts+=("$port_spec")
            fi
        fi
    done
    
    if [ ${#all_conflicts[@]} -gt 0 ]; then
        echo "[ERROR] Required ports are not available:" >&2
        echo "Conflicting ports: ${all_conflicts[*]}" >&2
        echo "Ports checked: 80 (nginx), 5672/5671 (RabbitMQ), 6379 (Redis), 8000-8088 (API services)" >&2
        echo "Please stop services using these ports first." >&2
        return 1
    fi
    
    return 0
}

# Create log directories
create_log_directories() {
    local services=("api-server" "user-api" "checkout-api" "voter-api" "nginx")
    
    for service in "${services[@]}"; do
        mkdir -p "${LOG_BASE}/${service}"
    done
    
    # Set ownership
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        chown -R "${SERVICE_USER}:${SERVICE_GROUP}" "$LOG_BASE"
    else
        echo "Warning: User '$SERVICE_USER' not found. Log directories created but ownership not set." >&2
    fi
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    # Detect install vs upgrade (use normalized numeric value)
    if [ "$INSTALL_ACTION_NUM" -gt 1 ]; then
        echo "Pre-install: Upgrade detected (action=$INSTALL_ACTION)"
        echo "Stopping services for upgrade..."
        systemctl stop platform-all.target 2>/dev/null || true
        systemctl disable platform-all.target 2>/dev/null || true
    else
        echo "Pre-install: Fresh installation (action=$INSTALL_ACTION)"
        echo "Checking port availability..."
        
        # Check port availability for fresh installs only
        if ! check_all_ports; then
            exit 1
        fi
    fi
    
    # Create log directories (for both install and upgrade)
    echo "Creating log directories..."
    create_log_directories
    
    echo "Pre-installation checks completed successfully."
}

# Execute main function
main "$@"

