# Build Process - RPM Creation Flow

## 📋 Input Files (Required BEFORE building)

### 1. Source Code (repo/)
```
repo/
├── api-server/          # Code available (POC)
│   ├── main.go
│   ├── config/
│   ├── handlers/
│   └── go.mod
├── user-api/            # Code (copied from api-server or from GitHub)
│   ├── main.go
│   ├── config/
│   ├── handlers/
│   └── go.mod
├── checkout-api/        # Code (copied from api-server or from GitHub)
│   ├── main.go
│   ├── config/
│   ├── handlers/
│   └── go.mod
└── voter-api/           # Code (copied from api-server or from GitHub)
    ├── main.go
    ├── config/
    ├── handlers/
    └── go.mod
```
**Action**: Code available in repo/ or cloned from GitHub

### 2. Configuration Files (apps/)
```
apps/
├── conf/                # Shared configs (AVAILABLE)
│   ├── env.properties
│   └── redis.properties
├── user-api/
│   └── user-api.properties      # AVAILABLE
├── checkout-api/
│   └── checkout-api.properties  # AVAILABLE
└── voter-api/
    └── voter-api.properties     # AVAILABLE
```
**Action**: These files are already available in the repo, no need to clone

### 3. Infrastructure Configs (infra/)
```
infra/
├── nginx/
│   └── platform.conf     # AVAILABLE
└── redis/
    └── platform-redis.conf # AVAILABLE
```
**Action**: These files are already available

### 4. Systemd Files (rpm/files/systemd/)
```
rpm/files/systemd/
├── platform-user-api.service      # AVAILABLE
├── platform-checkout-api.service  # AVAILABLE
├── platform-voter-api.service     # AVAILABLE
├── platform-infra.target           # AVAILABLE
└── platform-all.target            # AVAILABLE
```
**Action**: These files are already available

### 5. RPM Spec (rpm/specs/)
```
rpm/specs/
└── platform.spec   # AVAILABLE
```
**Action**: This file is already available

---

## 🔨 Build Process (When running `make build`)

### Step 1: Build Binaries for ALL Services in repo/
```
repo/api-server/    →  [go build]  →  repo/api-server/api-server (binary)
repo/user-api/      →  [go build]  →  repo/user-api/user-api (binary)
repo/checkout-api/  →  [go build]  →  repo/checkout-api/checkout-api (binary)
repo/voter-api/     →  [go build]  →  repo/voter-api/voter-api (binary)
```
**Note**: Script automatically detects all services with `main.go` in `repo/`

### Step 2: Copy Binaries → apps/
```
repo/api-server/api-server      →  apps/api-server/api-server
repo/user-api/user-api          →  apps/user-api/user-api
repo/checkout-api/checkout-api  →  apps/checkout-api/checkout-api
repo/voter-api/voter-api        →  apps/voter-api/voter-api
```

### Step 3: Prepare RPM SOURCES (Copy everything to rpm/SOURCES/)
```
rpm/SOURCES/
├── api-server/
│   └── api-server               # Binary (from apps/api-server/) - if available
├── user-api/
│   ├── user-api                 # Binary (from apps/user-api/)
│   └── user-api.properties      # Config (from apps/user-api/)
├── checkout-api/
│   ├── checkout-api             # Binary (from apps/checkout-api/)
│   └── checkout-api.properties  # Config (from apps/checkout-api/)
├── voter-api/
│   ├── voter-api                # Binary (from apps/voter-api/)
│   └── voter-api.properties     # Config (from apps/voter-api/)
├── conf/                         # Shared configs
│   ├── env.properties        # (from apps/conf/)
│   └── redis.properties      # (from apps/conf/)
├── platform.conf           # (from infra/nginx/)
├── platform-redis.conf     # (from infra/redis/)
├── platform-*.service      # (from rpm/files/systemd/)
├── platform-*.target       # (from rpm/files/systemd/)
└── print-version.sh        # (from rpm/platform/lib/)
```

### Step 4: Build RPM in Docker
```
rpm/SOURCES/  →  [rpmbuild]  →  dist/platform-1.0.0-1.x86_64.rpm
```

---

## 📦 Output (After building)

```
dist/
└── platform-1.0.0-1.x86_64.rpm  # ✅ Final RPM package
```

---

## 🎯 Quick Summary

**Required Input:**
1. ✅ Code in `repo/{service}/` (available or cloned from GitHub)
   - `repo/api-server/` (sample POC code)
   - `repo/user-api/` (code - available or cloned)
   - `repo/checkout-api/` (code - available or cloned)
   - `repo/voter-api/` (code - available or cloned)
2. ✅ Configs in `apps/` (already available)
3. ✅ Infrastructure configs in `infra/` (already available)
4. ✅ Systemd files in `rpm/files/systemd/` (already available)
5. ✅ RPM spec in `rpm/specs/` (already available)

**Build process:**
1. Build binaries from `repo/{service}/` for each service
2. Copy binaries → `apps/{service}/`
3. Copy everything (binaries + configs) to `rpm/SOURCES/`
4. Build RPM in Docker
5. Output: `dist/platform-*.rpm`

**Result:**
- 1 RPM file containing everything (service binaries, configs, systemd files)
- Each service has its own binary in `apps/{service}/`
- RPM spec only handles: user-api, checkout-api, voter-api (simple and explicit)

## Ref
- https://www.redhat.com/en/blog/create-rpm-package

