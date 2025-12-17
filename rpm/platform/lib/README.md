# Initialization Scripts

This directory contains post-installation initialization scripts.

## Purpose

Scripts in this directory are called during RPM installation (`%post` section) to:
- Create log directories
- Generate passwords/secrets
- Apply configurations
- Initialize services

## For Learning

For this basic project, you can add simplified versions of these scripts as needed.

## Usage in Spec File

```spec
%post
chmod +x /opt/platform/lib/*.sh
/opt/platform/lib/init-service.sh
```

