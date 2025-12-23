Name:           platform
Version:        1.0.0
Release:        1
Summary:        Platform - All Services
License:        MIT
URL:            https://github.com/duyhenryer/rpm-builder
BuildRequires:  golang >= 1.25
Requires:       nginx >= 1.20, redis >= 6.0, systemd

%description
Complete service platform with:
- api-server (port 8079)
- user-api (port 8080)
- checkout-api (port 8081)
- voter-api (port 8082)
- nginx reverse proxy (port 80)
- redis cache (port 6379)
This package provides a unified platform with all services bundled together.
Install once and get all services running with proper orchestration.

%prep
# No source preparation needed - we're using pre-built binaries

%build
# No build step needed - we're using pre-built binaries

%install
# Create directory structure
mkdir -p %{buildroot}/opt/platform/apps/conf/
mkdir -p %{buildroot}/opt/platform/apps/api-server/
mkdir -p %{buildroot}/opt/platform/apps/user-api/
mkdir -p %{buildroot}/opt/platform/apps/checkout-api/
mkdir -p %{buildroot}/opt/platform/apps/voter-api/
mkdir -p %{buildroot}/etc/nginx/conf.d/
mkdir -p %{buildroot}/etc/redis/
mkdir -p %{buildroot}/usr/lib/systemd/system/

# Copy service binaries
cp %{_sourcedir}/api-server/api-server %{buildroot}/opt/platform/apps/api-server/
cp %{_sourcedir}/user-api/user-api %{buildroot}/opt/platform/apps/user-api/
cp %{_sourcedir}/checkout-api/checkout-api %{buildroot}/opt/platform/apps/checkout-api/
cp %{_sourcedir}/voter-api/voter-api %{buildroot}/opt/platform/apps/voter-api/

# Copy shared configuration files
cp %{_sourcedir}/conf/*.properties %{buildroot}/opt/platform/apps/conf/

# Copy app-specific configuration files
cp %{_sourcedir}/api-server/api-server.properties %{buildroot}/opt/platform/apps/api-server/
cp %{_sourcedir}/user-api/user-api.properties %{buildroot}/opt/platform/apps/user-api/
cp %{_sourcedir}/checkout-api/checkout-api.properties %{buildroot}/opt/platform/apps/checkout-api/
cp %{_sourcedir}/voter-api/voter-api.properties %{buildroot}/opt/platform/apps/voter-api/

# Copy nginx config (nginx binary from repo)
cp %{_sourcedir}/platform.conf %{buildroot}/etc/nginx/conf.d/platform.conf
chmod 644 %{buildroot}/etc/nginx/conf.d/platform.conf

# Copy redis config (redis binary from repo)
# Note: This will be included in the main redis.conf or used as override
cp %{_sourcedir}/platform-redis.conf %{buildroot}/etc/redis/platform-redis.conf
chmod 644 %{buildroot}/etc/redis/platform-redis.conf

# Copy systemd files
cp %{_sourcedir}/platform-infra.target %{buildroot}/usr/lib/systemd/system/
cp %{_sourcedir}/platform-all.target %{buildroot}/usr/lib/systemd/system/
cp %{_sourcedir}/platform-api-server.service %{buildroot}/usr/lib/systemd/system/
cp %{_sourcedir}/platform-user-api.service %{buildroot}/usr/lib/systemd/system/
cp %{_sourcedir}/platform-checkout-api.service %{buildroot}/usr/lib/systemd/system/
cp %{_sourcedir}/platform-voter-api.service %{buildroot}/usr/lib/systemd/system/

# Copy initialization scripts
mkdir -p %{buildroot}/opt/platform/lib/
if [ -f %{_sourcedir}/print-version.sh ]; then
    cp %{_sourcedir}/print-version.sh %{buildroot}/opt/platform/lib/
    chmod +x %{buildroot}/opt/platform/lib/print-version.sh
fi

%files
%defattr(-,root,root,-)
# Service binaries
/opt/platform/apps/api-server/api-server
/opt/platform/apps/user-api/user-api
/opt/platform/apps/checkout-api/checkout-api
/opt/platform/apps/voter-api/voter-api
# Config files (marked as noreplace to preserve user modifications)
%config(noreplace) /opt/platform/apps/conf/*.properties
%config(noreplace) /opt/platform/apps/api-server/api-server.properties
%config(noreplace) /opt/platform/apps/user-api/user-api.properties
%config(noreplace) /opt/platform/apps/checkout-api/checkout-api.properties
%config(noreplace) /opt/platform/apps/voter-api/voter-api.properties
# Initialization scripts
/opt/platform/lib/print-version.sh
# Infrastructure configs
/etc/nginx/conf.d/platform.conf
/etc/redis/platform-redis.conf
# Systemd files
/usr/lib/systemd/system/platform-*

%pre
# Check if upgrading or installing
if [ $1 -gt 1 ]; then
    echo "%pre upgrade"
    echo "Stopping services for upgrade..."
    systemctl stop platform-all.target || true
    systemctl disable platform-all.target || true
else
    echo "%pre install"
    echo "Checking port availability..."
fi

# Check port availability (nginx, APIs, and redis)
portCheck=$(ss -tuln | grep -E ":(80|6379|8079|8080|8081|8082) " || true)
if [ -n "$portCheck" ]; then
    echo "[ERROR] Required ports (80, 6379, 8079, 8080, 8081, 8082) are not available:" >&2
    echo "$portCheck" >&2
    echo "Please stop services using these ports first." >&2
    exit 1
fi

# Create log directories
mkdir -p /var/log/platform/api-server
mkdir -p /var/log/platform/user-api
mkdir -p /var/log/platform/checkout-api
mkdir -p /var/log/platform/voter-api
mkdir -p /var/log/platform/nginx
chown -R nobody:nobody /var/log/platform

%post
# Set executable permissions for all service binaries
chmod +x /opt/platform/apps/api-server/api-server
chmod +x /opt/platform/apps/user-api/user-api
chmod +x /opt/platform/apps/checkout-api/checkout-api
chmod +x /opt/platform/apps/voter-api/voter-api

# Ensure Redis is running (from system repository)
# Note: If main redis.conf exists, you may need to include our config
# For Rocky Linux, we'll use a config snippet approach
if [ -f /etc/redis/redis.conf ]; then
    # Backup original config if not already backed up
    if [ ! -f /etc/redis/redis.conf.platform-backup ]; then
        cp /etc/redis/redis.conf /etc/redis/redis.conf.platform-backup
    fi
    # Include our config in the main config if not already included
    if ! grep -q "include /etc/redis/platform-redis.conf" /etc/redis/redis.conf; then
        echo "" >> /etc/redis/redis.conf
        echo "# Platform Redis Configuration" >> /etc/redis/redis.conf
        echo "include /etc/redis/platform-redis.conf" >> /etc/redis/redis.conf
    fi
else
    # If no main config exists, use ours as the primary config
    cp /etc/redis/platform-redis.conf /etc/redis/redis.conf
fi

systemctl enable redis || true
systemctl restart redis || systemctl start redis || true

# Reload nginx to pick up new config
systemctl reload nginx || true

# Reload systemd and start services
systemctl daemon-reload

# Run initialization scripts
if [ $1 -gt 1 ]; then
    echo "%post upgrade"
    /opt/platform/lib/print-version.sh upgrade || true
    systemctl enable platform-all.target
    systemctl start platform-all.target
else
    echo "%post install"
    /opt/platform/lib/print-version.sh install || true
    systemctl enable platform-all.target
    systemctl start platform-all.target
fi

echo "Platform installed successfully!"
echo "Services:"
echo "  - api-server: http://localhost:8079/"
echo "  - user-api: http://localhost:8080/"
echo "  - checkout-api: http://localhost:8081/"
echo "  - voter-api: http://localhost:8082/"
echo "  - nginx: http://localhost:80/"
echo "  - redis: localhost:6379"
echo ""
echo "Control all services:"
echo "  systemctl start platform-all.target"
echo "  systemctl stop platform-all.target"
echo "  systemctl status platform-all.target"

%preun
if [ $1 -eq 0 ]; then
    echo "%preun remove"
    echo "Stopping all services..."
    systemctl stop platform-all.target || true
    systemctl disable platform-all.target || true
    echo "Removing log directories..."
    rm -rf /var/log/platform
else
    echo "%preun upgrade"
fi

%postun
if [ $1 -eq 0 ]; then
    echo "%postun remove"
    systemctl daemon-reload
    echo "Platform removed successfully"
else
    echo "%postun upgrade"
    systemctl daemon-reload
fi

%changelog
* Mon Dec 23 2025 Duy Henry <duyhenryer@users.noreply.github.com> - 1.0.0-1
- Initial release of Platform
- Unified RPM package with all services
- Systemd target orchestration (platform-all.target, platform-infra.target)
- Nginx reverse proxy integration
- Redis configuration integration
- Version logging script (print-version.sh)
- Port availability checks during installation
- Automatic service startup after installation
- Services included: api-server (8079), user-api (8080), checkout-api (8081), voter-api (8082)
