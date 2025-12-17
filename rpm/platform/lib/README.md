# Initialization Scripts

This directory contains post-installation initialization scripts, following the production pattern from `mem-devops`.

## Purpose

Scripts in this directory are called during RPM installation (`%post` section) to:
- Create log directories
- Generate passwords/secrets
- Apply configurations
- Initialize services

## Production Pattern

In the production project (`mem-devops`), scripts include:
- `init-service.sh` - Creates log dirs, extracts archives, copies configs
- `password-generator.sh` - Generates secure passwords
- `password-apply.sh` - Applies passwords to configs
- `tls-generate.sh` - Generates TLS certificates
- `kek-generator.sh` - Key encryption key generation
- `nginx-port-change.sh` - Dynamic port configuration

## For Learning

For this basic project, you can add simplified versions of these scripts as needed.

## Usage in Spec File

```spec
%post
chmod +x /opt/platform/lib/*.sh
/opt/platform/lib/init-service.sh
```

