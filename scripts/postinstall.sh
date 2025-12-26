#!/bin/bash
# Post-installation script for Platform package
# Handles service setup, Redis/Nginx configuration, and service startup

set -e

# Script parameters:
# $1: Install action (1=install, 2=upgrade, 0=remove)
INSTALL_ACTION="${1:-1}"

# Platform installation paths
PLATFORM_BASE="/opt/platform"
APPS_DIR="${PLATFORM_BASE}/apps"
LIB_DIR="${PLATFORM_BASE}/lib"

# Service binaries
SERVICES=("api-server" "user-api" "checkout-api" "voter-api")

# Redis configuration
REDIS_MAIN_CONF="/etc/redis/redis.conf"
REDIS_PLATFORM_CONF="/etc/redis/platform-redis.conf"
REDIS_BACKUP_CONF="${REDIS_MAIN_CONF}.platform-backup"

# ============================================================================
# Helper Functions
# ============================================================================

# Set executable permissions for service binaries
set_binary_permissions() {
    echo "Setting executable permissions for service binaries..."
    for service in "${SERVICES[@]}"; do
        local binary="${APPS_DIR}/${service}/${service}"
        if [ -f "$binary" ]; then
            chmod +x "$binary"
            echo "  [OK] Set permissions for ${service}"
        else
            echo "  [WARNING] Binary not found: $binary" >&2
        fi
    done
}

# Configure Redis integration
configure_redis() {
    echo "Configuring Redis integration..."
    
    if [ -f "$REDIS_MAIN_CONF" ]; then
        # Backup original config if not already backed up
        if [ ! -f "$REDIS_BACKUP_CONF" ]; then
            cp "$REDIS_MAIN_CONF" "$REDIS_BACKUP_CONF"
            echo "  [OK] Backed up original Redis config"
        fi
        
        # Include our config in the main config if not already included
        if ! grep -q "include ${REDIS_PLATFORM_CONF}" "$REDIS_MAIN_CONF"; then
            echo "" >> "$REDIS_MAIN_CONF"
            echo "# Platform Redis Configuration" >> "$REDIS_MAIN_CONF"
            echo "include ${REDIS_PLATFORM_CONF}" >> "$REDIS_MAIN_CONF"
            echo "  [OK] Added platform Redis config to main config"
        else
            echo "  [OK] Platform Redis config already included"
        fi
    else
        # If no main config exists, use ours as the primary config
        if [ -f "$REDIS_PLATFORM_CONF" ]; then
            cp "$REDIS_PLATFORM_CONF" "$REDIS_MAIN_CONF"
            echo "  [OK] Created Redis config from platform config"
        else
            echo "  [WARNING] Platform Redis config not found: $REDIS_PLATFORM_CONF" >&2
        fi
    fi
    
    # Enable and start Redis
    # Detect Redis service name (redis on RPM, redis-server on DEB)
    # Loop through known service names and use the first one that exists
    REDIS_SERVICE=""
    for service_name in redis redis-server; do
        # Check if service unit file exists
        if systemctl list-unit-files --type=service --no-pager 2>/dev/null | grep -q "^${service_name}.service"; then
            REDIS_SERVICE="$service_name"
            break
        fi
        # Also check if service is available (even if not installed)
        if systemctl list-units --type=service --all --no-pager 2>/dev/null | grep -q "${service_name}.service"; then
            REDIS_SERVICE="$service_name"
            break
        fi
    done
    
    if [ -z "$REDIS_SERVICE" ]; then
        echo "  [WARNING] Redis service not found (checked: redis, redis-server)" >&2
        echo "  [WARNING] Redis may need to be installed separately" >&2
        echo "  [WARNING] Continuing without starting Redis service..." >&2
    else
        echo "  [INFO] Found Redis service: $REDIS_SERVICE"
        systemctl enable "$REDIS_SERVICE" 2>/dev/null || true
        if systemctl is-active --quiet "$REDIS_SERVICE" 2>/dev/null; then
            systemctl restart "$REDIS_SERVICE" 2>/dev/null || true
            echo "  [OK] Redis ($REDIS_SERVICE) restarted"
        else
            systemctl start "$REDIS_SERVICE" 2>/dev/null || true
            if systemctl is-active --quiet "$REDIS_SERVICE" 2>/dev/null; then
                echo "  [OK] Redis ($REDIS_SERVICE) started"
            else
                echo "  [WARNING] Failed to start Redis ($REDIS_SERVICE)" >&2
            fi
        fi
    fi
}

# Reload Nginx configuration
reload_nginx() {
    echo "Reloading Nginx configuration..."
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx 2>/dev/null || true
        echo "  [OK] Nginx reloaded"
    else
        echo "  [WARNING] Nginx is not running" >&2
    fi
}

# Reload systemd daemon
reload_systemd() {
    echo "Reloading systemd daemon..."
    systemctl daemon-reload
    echo "  [OK] Systemd daemon reloaded"
}

# Run initialization scripts
run_init_scripts() {
    local action=$1
    local init_script="${LIB_DIR}/print-version.sh"
    
    if [ -f "$init_script" ] && [ -x "$init_script" ]; then
        echo "Running initialization script..."
        "$init_script" "$action" 2>/dev/null || true
        echo "  [OK] Initialization script executed"
    else
        echo "  [WARNING] Initialization script not found or not executable: $init_script" >&2
    fi
}

# Enable and start platform services
start_platform_services() {
    echo "Enabling and starting platform services..."
    systemctl enable platform-all.target 2>/dev/null || true
    
    if systemctl start platform-all.target 2>/dev/null; then
        echo "  [OK] Platform services started"
    else
        echo "  [WARNING] Failed to start platform services" >&2
        echo "    You may need to check service status manually" >&2
    fi
}

# Display installation success message
display_success_message() {
    echo ""
    echo "=========================================="
    echo "Platform installed successfully!"
    echo "=========================================="
    echo ""
    echo "Services:"
    echo "  - api-server:    http://localhost:8079/"
    echo "  - user-api:      http://localhost:8080/"
    echo "  - checkout-api:  http://localhost:8081/"
    echo "  - voter-api:     http://localhost:8082/"
    echo "  - nginx:         http://localhost:80/"
    echo "  - redis:         localhost:6379"
    echo ""
    echo "Control all services:"
    echo "  systemctl start platform-all.target"
    echo "  systemctl stop platform-all.target"
    echo "  systemctl status platform-all.target"
    echo ""
}

# ============================================================================
# Main Script Logic
# ============================================================================

main() {
    # Detect install vs upgrade
    if [ "$INSTALL_ACTION" -gt 1 ]; then
        echo "Post-install: Upgrade detected (action=$INSTALL_ACTION)"
    else
        echo "Post-install: Fresh installation (action=$INSTALL_ACTION)"
    fi
    
    # Set binary permissions
    set_binary_permissions
    
    # Configure Redis
    configure_redis
    
    # Reload Nginx
    reload_nginx
    
    # Reload systemd
    reload_systemd
    
    # Run initialization scripts
    run_init_scripts "$([ "$INSTALL_ACTION" -gt 1 ] && echo "upgrade" || echo "install")"
    
    # Start platform services
    start_platform_services
    
    # Display success message
    display_success_message
}

# Execute main function
main "$@"

