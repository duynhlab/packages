# plan-spec.md — Monorepo SPEC (1 file) + RPM build (v2)

> **Status**: Draft v2, 2026-05-24. Đã chốt decision với user (xem §0). Đây là tài liệu chính để bắt đầu Phase S0-S5.
>
> **Inspiration sources**:
> - **MOCM** (`Opswat/mem-devops/docker-rpm-build`) — mega-RPM, 1 SPEC, stage external rồi `cp -rf` vào `%{buildroot}`, scriptlet inline orchestrate nginx/redis/rabbitmq + init-service.sh + password-generator.sh.
> - **ton-blockchain/packages** — repack-only SPEC (`%build` empty, `%install` copy file), createrepo_c, commit `rpm/` vào branch, serve qua GitHub Pages.
>
> **duynhlab áp dụng**: Mega-RPM kiểu MOCM (1 file SPEC = 1 RPM = full platform) + distribution kiểu TON (gh-pages + createrepo_c).

---

## 0. Decision đã chốt

| ID | Decision | Note |
|---|---|---|
| **S-D1** | Bỏ nFPM hoàn toàn, chuyển sang RPM SPEC + `rpmbuild`/`mock` | Đã chọn |
| **S-D2** | **Monorepo SPEC** — 1 file `specs/duynhlab.spec` build ra **1 RPM duy nhất** `duynhlab-X.Y.Z.x86_64.rpm` chứa toàn bộ 8 backend + frontend + common tooling + config templates nginx/valkey/postgres | Pattern MOCM. Chi tiết §2-3. |
| **S-D3** | `rpmbuild` cho dev local, `mock` chroot cho CI/release | |
| **S-D4** | KHÔNG build Go từ source trong chroot. Service repos build binary tarball, packages repo chỉ stage + repack | `%build` empty, `%install` copy từ `/workplace/duynhlab/` (giống MOCM `/workplace/mocm/`) |
| **S-D5** | `%autorelease` + `%autochangelog` (EPEL/rpmautospec) | |
| **S-D6** | `%global debug_package %{nil}` (Go binary strip-DWARF không dùng được) | |
| **S-D7** | `%ghost` cho env file + scriptlet generate password tại postinstall | |
| **S-D8** | Systemd macros chuẩn (`%systemd_post`/`%systemd_preun`/`%systemd_postun_with_restart`) | Per service trong scriptlet |
| **S-D9** | Target initial: EL9 (Rocky/Alma) x86_64 | aarch64 + EL10 ở Phase S5 |
| **S-D10** | `duynhlab-gen-env` CLI bash, ship trong mega-RPM | |
| **S-D11** | Mega-RPM cũng ship template config cho **nginx, valkey, postgresql tuning** — install-service.sh copy vào `/etc/nginx/conf.d/`, `/etc/valkey/`, `/etc/postgresql/conf.d/` (idempotent) | Pattern MOCM |
| **S-D12** | Distribution: GitHub Pages YUM repo, branch `gh-pages`, `createrepo_c` | Pattern TON |

---

## 1. Bài học từ 2 nguồn tham khảo

### 1.1 MOCM (`mocm.spec` — 121 dòng, build ra 1 RPM gói 50+ services)

**Pattern**:
1. **External staging**: Build pipeline (Docker container) chuẩn bị toàn bộ filesystem vào `/workplace/mocm/` trước khi gọi `rpmbuild`.
2. **SPEC tối giản**: `%prep` rỗng, `%build` rỗng, `%install` chỉ `cp -rf /workplace/mocm/** %{buildroot}/opt/mocm/` + copy systemd units.
3. **Scriptlet logic**: `%pre` check upgrade vs install, stop services trên upgrade, port check. `%post` tạo `/var/log/mocm/`, chmod +x, gọi `init-service.sh` + `tls-generate.sh` + `kek-generator.sh` + `password-generator.sh`.
4. **Service taxonomy**:
   - `mocm-infra.target` = wraps external infra (nginx/redis/rabbitmq/mongodb).
   - `mocm-all.target` = `Wants=` tất cả service units + `After=mocm-infra.target`.
   - Per-service unit: `After=mocm-infra.target`, `PartOf=mocm-all.target`, `EnvironmentFile=` nhiều file (`go-env.properties`, `go-mongo.properties`, `<svc>.properties`, `<svc>.override`).
5. **Config strategy**:
   - Template config trong `/opt/mocm/etc/`, `/opt/mocm/nginx/`, `/opt/mocm/redis/`, `/opt/mocm/rabbitmq/`.
   - `init-service.sh` copy sang `/etc/opt/mocm/`, `/etc/nginx/`, `/etc/redis/`, `/etc/rabbitmq/` (idempotent, skip nếu file tồn tại).
   - Per-service config: `/opt/mocm/apps/<svc>/<svc>.properties` (ship) + `/opt/mocm/apps/<svc>/<svc>.override` (admin tạo, gitignored).
6. **Secret handling**:
   - `secret-tpl/*.secret.tpl` — template với placeholder.
   - `password-generator.sh` render → `/etc/opt/mocm/*.secret`.
   - `password-encrypt.sh` mã hoá → `*.secret.enc`.
   - Systemd `LoadCredentialEncrypted=` giải mã runtime.
   - Idempotent qua `secret_version.properties`.
7. **SELinux**: `semanage port` + `setsebool` trong `%post`.
8. **Logrotate**: ship `/opt/mocm/logrotate/` → copy `/etc/logrotate.d/` trong init-service.sh.

**Điểm hay copy**:
- Tách rõ /opt (immutable, ship by RPM) vs /etc/opt (mutable, init by scriptlet).
- `init-service.sh` = idempotent migrator, chạy mỗi `%post`, an toàn cho upgrade.
- `<svc>.override` pattern cho per-host customization mà không động đến file shipped.
- Versioned secret init (`secret_version.properties`).
- Port check trong `%pre` (block install nếu port conflict).

**Điểm cần tránh**:
- `cp -rf /workplace/mocm/**` — fragile path, hardcoded build location. Sẽ thay bằng `%setup -q` từ tarball.
- `Requires: nginx >= ..., redis >= ..., rabbitmq-server >= ..., erlang >= ..., openssl >= ..., selinux-policy >= ...` — pin version chặt, dễ vỡ. Sẽ dùng minor-floor only (`nginx >= 1.20`).
- `mocm-all.target` `Wants=` 50+ services trong 1 dòng — không scale. Sẽ render dynamic từ `services.yaml`.
- Không có `%autorelease` / `%autochangelog`.
- `%files /opt/mocm/**` quá broad — không track per-file mode/owner.

### 1.2 TON (`ton.spec` — repack pattern)

**Pattern**:
1. Tải binary tarball từ upstream release.
2. Reshape vào layout chuẩn (`bin/`, `lib/`, `share/`).
3. `tar` thành `Source0`.
4. `rpmbuild -bb` với SPEC ngắn: `%build` empty, `%install` chỉ `cp -ar bin/* lib/* share/* %{buildroot}/...`.
5. Sau khi build: `createrepo_c rpm/x86_64/` + commit folder `rpm/` → GitHub Pages serve YUM repo.

**Điểm copy cho duynhlab**:
- `%build` empty pattern.
- Source tarball staging trước rpmbuild (không build trong chroot).
- `createrepo_c` + GitHub Pages.
- Multi-arch dir layout `rpm/{x86_64,aarch64}/` cho tương lai.

---

## 2. Kiến trúc S-D2 chi tiết — Monorepo SPEC

### 2.1 Tổng quan

```
specs/duynhlab.spec   (1 file ~400 dòng)
        ↓ rpmbuild -ba
1 SRPM + 1 RPM:
  duynhlab-2026.05.20-1.el9.x86_64.rpm    (~80MB, gói toàn bộ)
  duynhlab-2026.05.20-1.el9.src.rpm
```

**Tên RPM**: `duynhlab` (không suffix `-platform`/`-common` nữa).

**1 RPM duy nhất chứa**:
- 8 backend binaries (`auth-service`, `user-service`, ..., `shipping-service`)
- 1 frontend static dist (`/opt/duynhlab/frontend/dist/`)
- 4 CLI tools (`duynhlab-ctl`, `duynhlab-db-setup`, `duynhlab-db-migrate`, `duynhlab-gen-password`, `duynhlab-gen-env`)
- Toàn bộ migrations SQL
- Toàn bộ systemd units + 2 target
- Template config cho nginx, valkey, postgresql
- Lib scripts (init-service.sh, password-generator.sh, …)
- Logrotate configs
- `services.yaml` registry

### 2.2 Filesystem layout chính thức

```
/opt/duynhlab/                              # immutable, ship by RPM
├── auth/
│   ├── bin/auth-service                    # 0755 duynhlab:duynhlab
│   ├── BINARY_VERSION                      # 0644 root:root
│   ├── SCHEMA_VERSION
│   └── migrations/sql/                     # *.up.sql, *.down.sql
├── user/  product/  cart/  order/  review/  notification/  shipping/
│   (cùng layout)
├── frontend/
│   └── dist/                               # index.html, assets/
├── etc/                                    # template configs
│   ├── env-global.properties               # shared LOG_LEVEL, OBSERVABILITY
│   ├── services.yaml                       # source of truth
│   └── nginx/
│       ├── duynhlab.conf                   # main vhost
│       ├── upstream-backend.conf           # render từ services.yaml
│       └── locations-*.conf
├── valkey/
│   └── valkey.conf                         # template
├── postgresql/
│   ├── duynhlab-tuning.conf                # drop-in /etc/postgresql/conf.d/
│   ├── pg_hba-duynhlab.conf                # snippet append vào pg_hba.conf
│   └── bootstrap.sql                       # CREATE USER/DB cho 8 service
├── lib/                                    # bash scripts
│   ├── init-service.sh                     # idempotent migrator
│   ├── password-generator.sh
│   ├── password-apply.sh
│   ├── duynhlab-ctl                        # → symlink /usr/bin/
│   ├── duynhlab-db-setup
│   ├── duynhlab-db-migrate                 # golang-migrate binary
│   ├── duynhlab-gen-env
│   └── duynhlab-gen-password
├── logrotate/
│   ├── duynhlab-services                   # journald → /var/log/duynhlab/
│   └── duynhlab-nginx
└── secret-tpl/                             # template với __PLACEHOLDER__
    ├── auth.env.tpl
    ├── user.env.tpl
    └── ... (8 file)

/etc/opt/duynhlab/                          # mutable, init by scriptlet
├── env-global.properties                   # copy từ /opt/duynhlab/etc/ trên %post
├── services.yaml                           # copy + admin có thể edit
├── auth.env                                # %ghost — generate bởi gen-env
├── user.env  ...  shipping.env             # %ghost
├── frontend.env                            # %ghost
└── secret_version.properties               # tracking đã init password chưa

/etc/nginx/conf.d/
└── duynhlab.conf                           # copy từ /opt/duynhlab/etc/nginx/duynhlab.conf

/etc/valkey/conf.d/
└── duynhlab.conf                           # snippet

/etc/postgresql/<version>/conf.d/           # hoặc /var/lib/pgsql/data/conf.d/
└── duynhlab-tuning.conf

/etc/logrotate.d/
├── duynhlab-services
└── duynhlab-nginx

/usr/bin/                                   # symlink hoặc copy
├── duynhlab-ctl  →  /opt/duynhlab/lib/duynhlab-ctl
├── duynhlab-db-setup  →  ...
├── duynhlab-db-migrate
├── duynhlab-gen-env
└── duynhlab-gen-password

/usr/lib/systemd/system/
├── duynhlab-infra.target                   # Wants=nginx valkey postgresql
├── duynhlab-platform.target                # After=infra, Wants=8 backend + frontend
├── duynhlab-auth.service                   # PartOf=platform, After=infra
├── duynhlab-user.service  ...  (8 backend)
└── duynhlab-frontend.service               # nginx reload wrapper (hoặc dùng nginx trực tiếp)

/var/log/duynhlab/                          # created by init-service.sh
├── auth/  user/  ...  (8 dir)
└── nginx/

/var/lib/duynhlab/                          # state nếu cần (cache, run-once flags)
```

### 2.3 Service taxonomy (systemd targets)

Adapt từ MOCM `mocm-infra.target` + `mocm-all.target`:

```
duynhlab-infra.target
  Wants= nginx.service valkey.service postgresql.service
  (chỉ group external infra, không tự start; admin enable nếu muốn)

duynhlab-platform.target
  After= duynhlab-infra.target
  Wants= duynhlab-auth.service duynhlab-user.service duynhlab-product.service
         duynhlab-cart.service duynhlab-order.service duynhlab-review.service
         duynhlab-notification.service duynhlab-shipping.service
         duynhlab-frontend-reload.service
  → admin chỉ cần: systemctl enable --now duynhlab-platform.target

duynhlab-<svc>.service (per-service, 8 backend)
  After= duynhlab-infra.target
  PartOf= duynhlab-platform.target
  EnvironmentFile= /etc/opt/duynhlab/env-global.properties
  EnvironmentFile= /etc/opt/duynhlab/<svc>.env
  EnvironmentFile= -/etc/opt/duynhlab/<svc>.override
  User= duynhlab
  ExecStart= /opt/duynhlab/<svc>/bin/<svc>-service
  Restart= always
  RestartSec= 5
  StandardOutput= journal
  StandardError= journal

duynhlab-frontend-reload.service (one-shot, tuỳ chọn)
  Type= oneshot
  ExecStart= /usr/sbin/nginx -t
  ExecStart= /bin/systemctl reload nginx.service
  (Frontend không cần unit riêng — nginx serve trực tiếp /opt/duynhlab/frontend/dist/)
```

Cả 2 target được render từ `services.yaml` bởi `scripts/render-systemd.sh` tại build time (không runtime).

### 2.4 Config strategy chi tiết

#### Per-service env file

```
/opt/duynhlab/secret-tpl/auth.env.tpl    (ship by RPM, mode 0644)
  SERVICE_NAME=auth
  PORT=8001
  DB_HOST=localhost
  DB_PORT=5432
  DB_NAME=duynhlab_auth
  DB_USER=duynhlab_auth_app
  DB_PASSWORD=__GENERATED__
  DB_SSLMODE=disable
  DB_POOL_MAX=25
  REDIS_URL=redis://localhost:6379/0
  LOG_LEVEL=info

/etc/opt/duynhlab/auth.env               (%ghost, mode 0640 root:duynhlab)
  → gen-env.sh render từ tpl + random 32-char password
  → idempotent: nếu file exists, skip
```

#### Nginx

```
/opt/duynhlab/etc/nginx/duynhlab.conf    (ship)
  upstream auth      { server 127.0.0.1:8001; }
  upstream user      { server 127.0.0.1:8002; }
  ...
  server {
    listen 80;
    server_name _;
    root /opt/duynhlab/frontend/dist;
    location /api/auth/    { proxy_pass http://auth; }
    location /api/user/    { proxy_pass http://user; }
    ...
    location / { try_files $uri $uri/ /index.html; }
  }

%post → init-service.sh:
  if [ ! -f /etc/nginx/conf.d/duynhlab.conf ]; then
    cp /opt/duynhlab/etc/nginx/duynhlab.conf /etc/nginx/conf.d/
    nginx -t && systemctl reload nginx
  fi
```

#### Valkey (Redis fork — drop-in replacement, dùng từ EL9 `valkey` package)

```
/opt/duynhlab/valkey/duynhlab.conf       (ship, snippet)
  # duynhlab valkey tuning
  maxmemory 1gb
  maxmemory-policy allkeys-lru
  save ""
  appendonly no

%post → init-service.sh:
  if [ ! -f /etc/valkey/conf.d/duynhlab.conf ]; then
    install -Dm644 /opt/duynhlab/valkey/duynhlab.conf /etc/valkey/conf.d/duynhlab.conf
  fi
```

Note: RHEL 9.4+ ship `valkey` package (replacing redis). `Requires: valkey >= 7.2` hoặc dùng `redis` cũ.

#### PostgreSQL

```
/opt/duynhlab/postgresql/duynhlab-tuning.conf    (ship)
  # duynhlab tuning
  max_connections = 300
  shared_buffers = 512MB
  effective_cache_size = 2GB
  work_mem = 8MB
  maintenance_work_mem = 128MB

/opt/duynhlab/postgresql/bootstrap.sql           (ship)
  -- run by `duynhlab-db-setup bootstrap` (manual, not %post)
  CREATE USER duynhlab_auth_app PASSWORD :auth_password;
  CREATE USER duynhlab_auth_migrator PASSWORD :migrator_password SUPERUSER;
  CREATE DATABASE duynhlab_auth OWNER duynhlab_auth_app;
  ... (8 services)

%post → KHÔNG tự bootstrap DB (per D19). Chỉ print hint:
  "Run: SUPERUSER_DSN=... duynhlab-db-setup bootstrap"
```

### 2.5 Lib scripts (ship trong RPM)

| Script | Role | Khi chạy |
|---|---|---|
| `init-service.sh` | Idempotent migrator: tạo `/var/log/duynhlab/<svc>/`, copy template → `/etc/opt/duynhlab/`, `/etc/nginx/conf.d/`, `/etc/valkey/conf.d/`, `/etc/logrotate.d/`. Chmod binary. | `%post` mỗi lần install/upgrade |
| `password-generator.sh` | Loop qua 8 service + frontend, render `secret-tpl/*.env.tpl` → `/etc/opt/duynhlab/*.env` với random 32-char password. Idempotent qua `secret_version.properties`. | `%post` first-install only |
| `password-apply.sh` | (optional) Apply password vào running PG | Manual |
| `duynhlab-ctl` | CLI: list/start/stop/restart/status/enable/disable/logs/health/version/config/ports. | User runtime |
| `duynhlab-db-setup` | Bootstrap DB + users + migrate. | Manual |
| `duynhlab-db-migrate` | golang-migrate binary | Called by db-setup |
| `duynhlab-gen-env` | Render 1 env file từ tpl + random pass | Called by password-generator hoặc manual |
| `duynhlab-gen-password` | Stdout 1 random password | Helper |

---

## 3. SPEC file (skeleton)

`specs/duynhlab.spec`:

```spec
%global duynhlab_user    duynhlab
%global duynhlab_group   duynhlab
%global duynhlab_prefix  /opt/duynhlab
%global duynhlab_etc     /etc/opt/duynhlab
%global duynhlab_log     /var/log/duynhlab
%global duynhlab_state   /var/lib/duynhlab

# Go binary đã strip — không tạo debuginfo
%global debug_package %{nil}

# Skip mangle shebang trong binary lib
%global __brp_mangle_shebangs_exclude_from %{duynhlab_prefix}/lib/.*\.sh$

Name:           duynhlab
Version:        %{?_duynhlab_version}%{!?_duynhlab_version:2026.05.20}
Release:        %autorelease
Summary:        duynhlab e-commerce platform
License:        Proprietary
URL:            https://duynhlab.github.io/packages
Vendor:         duynhlab
Packager:       duynhlab ops <ops@duynhlab.io>

# Single source: staging tarball pre-built bởi scripts/stage-all.sh
Source0:        duynhlab-%{version}-staging.tar.gz

BuildRequires:  systemd-rpm-macros
BuildRequires:  rpmautospec-rpm-macros

Requires:       systemd
Requires:       bash >= 4.0
Requires:       coreutils
Requires:       nginx >= 1.20
Requires:       postgresql >= 14
# Valkey ưu tiên (EL9.4+); fallback redis nếu cần
Requires:       (valkey >= 7.2 or redis >= 6)
Requires(pre):  shadow-utils
%{?systemd_requires}

Recommends:     nginx >= 1.24
Recommends:     valkey >= 8
Recommends:     postgresql-server >= 16

%description
duynhlab e-commerce platform: 8 Go microservices (auth, user, product, cart,
order, review, notification, shipping) + frontend SPA + shared CLI tools +
config templates for nginx, valkey, postgresql.

Includes:
  * Per-service systemd units + duynhlab-platform.target
  * duynhlab-ctl, duynhlab-db-setup, duynhlab-db-migrate CLI
  * Idempotent init scripts (config templates → /etc/opt/duynhlab/)
  * Random password generation at first install (preserved on upgrade)

%prep
%setup -q -c -T -n duynhlab-%{version}
tar xzf %{S:0} --strip-components=1

%build
# Nothing to build — Go binaries pre-built by service repos, frontend pre-built by Vite.

%install
# Tarball đã có sẵn layout staging/opt/duynhlab/... và staging/usr/lib/systemd/...
# Mirror y nguyên vào buildroot.

mkdir -p %{buildroot}%{duynhlab_prefix}
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_bindir}

cp -rp opt/duynhlab/* %{buildroot}%{duynhlab_prefix}/
cp -p systemd/* %{buildroot}%{_unitdir}/

# Symlink lib tools → /usr/bin (hoặc copy nếu cần)
for tool in duynhlab-ctl duynhlab-db-setup duynhlab-db-migrate \
            duynhlab-gen-env duynhlab-gen-password; do
  ln -sf %{duynhlab_prefix}/lib/$tool %{buildroot}%{_bindir}/$tool
done

%check
# Sanity: ELF check 8 backend binaries
for svc in auth user product cart order review notification shipping; do
  bin="%{buildroot}%{duynhlab_prefix}/${svc}/bin/${svc}-service"
  test -x "$bin"
  file "$bin" | grep -q "ELF.*executable"
done

# Frontend dist exists
test -f %{buildroot}%{duynhlab_prefix}/frontend/dist/index.html

# Systemd unit syntax
systemd-analyze verify %{buildroot}%{_unitdir}/duynhlab-*.service 2>&1 | grep -v "Failed to" || true

%pre
# Upgrade: stop platform target nicely, daemon-reload
if [ $1 -gt 1 ]; then
  systemctl stop duynhlab-platform.target 2>/dev/null || :
fi

# Port conflict check (only on first install)
if [ $1 -eq 1 ]; then
  for port in 8001 8002 8003 8004 8005 8006 8007 8008; do
    if ss -tlnH 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"; then
      echo "[ERROR] Port ${port} is already in use." >&2
      exit 1
    fi
  done
fi

# Create user/group
getent group %{duynhlab_group} >/dev/null || \
  groupadd -r %{duynhlab_group}
getent passwd %{duynhlab_user} >/dev/null || \
  useradd -r -g %{duynhlab_group} -d %{duynhlab_prefix} -s /sbin/nologin \
    -c "duynhlab platform service account" %{duynhlab_user}

exit 0

%post
# 1. Init log dirs, copy template configs, chmod binaries
chmod +x %{duynhlab_prefix}/lib/*.sh
%{duynhlab_prefix}/lib/init-service.sh

# 2. Generate env files + passwords (first install only, or if missing)
%{duynhlab_prefix}/lib/password-generator.sh

# 3. Reload systemd, register units
%systemd_post duynhlab-platform.target
for svc in auth user product cart order review notification shipping; do
  %systemd_post duynhlab-${svc}.service
done

# 4. Reload nginx if active (config dropped by init-service.sh)
if systemctl is-active --quiet nginx; then
  nginx -t && systemctl reload nginx || :
fi

# 5. Print hint
cat <<'EOF'

================================================================
  duynhlab installed. Next steps (as root):

    # 1. Setup PostgreSQL (one-time):
    SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \
      duynhlab-db-setup bootstrap

    # 2. Run migrations:
    duynhlab-db-setup migrate

    # 3. Start platform:
    systemctl enable --now duynhlab-platform.target

    # 4. Verify:
    duynhlab-ctl status
    curl http://localhost/health
================================================================
EOF

exit 0

%preun
# Upgrade ($1=1) → no-op (handled by %pre of new pkg)
# Remove   ($1=0) → stop + disable
if [ $1 -eq 0 ]; then
  systemctl stop duynhlab-platform.target 2>/dev/null || :
  systemctl disable duynhlab-platform.target 2>/dev/null || :
  for svc in auth user product cart order review notification shipping; do
    %systemd_preun duynhlab-${svc}.service
  done
  %systemd_preun duynhlab-platform.target
fi

exit 0

%postun
# Upgrade ($1=1): restart services with new binary
if [ $1 -eq 1 ]; then
  for svc in auth user product cart order review notification shipping; do
    %systemd_postun_with_restart duynhlab-${svc}.service
  done
fi
# Remove ($1=0): KEEP /etc/opt/duynhlab/ (env+passwords), KEEP DB
# Admin tự xoá nếu muốn:
#   rm -rf /etc/opt/duynhlab /var/log/duynhlab
exit 0

%files
%defattr(-,root,root,-)

# Binaries + assets
%dir %attr(0755, %{duynhlab_user}, %{duynhlab_group}) %{duynhlab_prefix}
%attr(0755, %{duynhlab_user}, %{duynhlab_group}) %{duynhlab_prefix}/auth
%attr(0755, %{duynhlab_user}, %{duynhlab_group}) %{duynhlab_prefix}/auth/bin/auth-service
# ... (lặp 8 service) — hoặc dùng glob:
%{duynhlab_prefix}/auth/
%{duynhlab_prefix}/user/
%{duynhlab_prefix}/product/
%{duynhlab_prefix}/cart/
%{duynhlab_prefix}/order/
%{duynhlab_prefix}/review/
%{duynhlab_prefix}/notification/
%{duynhlab_prefix}/shipping/
%{duynhlab_prefix}/frontend/

# Templates + libs
%{duynhlab_prefix}/etc/
%{duynhlab_prefix}/nginx/
%{duynhlab_prefix}/valkey/
%{duynhlab_prefix}/postgresql/
%{duynhlab_prefix}/secret-tpl/
%{duynhlab_prefix}/logrotate/
%attr(0755, root, root) %{duynhlab_prefix}/lib/*

# CLI symlinks
%{_bindir}/duynhlab-ctl
%{_bindir}/duynhlab-db-setup
%{_bindir}/duynhlab-db-migrate
%{_bindir}/duynhlab-gen-env
%{_bindir}/duynhlab-gen-password

# Systemd units
%{_unitdir}/duynhlab-infra.target
%{_unitdir}/duynhlab-platform.target
%{_unitdir}/duynhlab-auth.service
%{_unitdir}/duynhlab-user.service
%{_unitdir}/duynhlab-product.service
%{_unitdir}/duynhlab-cart.service
%{_unitdir}/duynhlab-order.service
%{_unitdir}/duynhlab-review.service
%{_unitdir}/duynhlab-notification.service
%{_unitdir}/duynhlab-shipping.service

# Ghost configs (managed by scriptlet, not RPM-owned content)
%dir %attr(0750, root, %{duynhlab_group}) %{duynhlab_etc}
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/auth.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/user.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/product.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/cart.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/order.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/review.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/notification.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/shipping.env
%ghost %attr(0644, root, root) %{duynhlab_etc}/secret_version.properties
%ghost %attr(0644, root, root) %{duynhlab_etc}/env-global.properties
%ghost %attr(0644, root, root) %{duynhlab_etc}/services.yaml

# Log directories (created by init-service.sh, owned by service user)
%ghost %attr(0755, %{duynhlab_user}, %{duynhlab_group}) %{duynhlab_log}

%changelog
%autochangelog
```

---

## 4. Build pipeline

### 4.1 Local flow

```
service repos (sibling checkout)                  frontend repo
        │                                                │
        ▼                                                ▼
scripts/build-local.sh <svc>                  npm ci && npm run build
  → build/<svc>/raw/<svc>-X.Y.Z-linux-amd64.tar.gz   → dist.tar.gz
        │                                                │
        └─────────────────┬──────────────────────────────┘
                          ▼
            scripts/stage-all.sh
              → build/staging/
                  opt/duynhlab/{auth,...,frontend,lib,etc,...}/
                  systemd/duynhlab-*.{service,target}
              → tar czf build/sources/duynhlab-VERSION-staging.tar.gz staging/
                          │
                          ▼
            scripts/build-rpm.sh
              local:   rpmbuild -ba specs/duynhlab.spec
                         --define "_topdir $PWD/build/rpmbuild"
                         --define "_sourcedir $PWD/build/sources"
                         --define "_duynhlab_version $VERSION"
              CI:      mock -r rocky-9-x86_64 \
                         --sources build/sources \
                         --spec specs/duynhlab.spec
                          │
                          ▼
            dist/duynhlab-2026.05.20-1.el9.x86_64.rpm   (~80MB)
            dist/duynhlab-2026.05.20-1.el9.src.rpm
                          │
                          ▼
            scripts/smoke-install.sh
              dnf localinstall dist/*.rpm trong Rocky 9 container
              → assert: install ok, env generated, services registered,
                        reinstall preserve, uninstall preserve /etc/opt
```

### 4.2 Scripts cần viết mới / rewrite

| Script | Status | Mục đích |
|---|---|---|
| `scripts/build-local.sh` | ✅ giữ nguyên | Build 1 service từ sibling repo → tarball trong `build/<svc>/raw/` |
| `scripts/stage-all.sh` | 🆕 mới | Stage tất cả 9 service + lib + configs vào `build/staging/`, tar thành `Source0` |
| `scripts/render-systemd.sh` | ✅ rewrite | Render 8 backend `.service` + 2 `.target` từ `services.yaml` → `build/staging/systemd/` |
| `scripts/render-nginx.sh` | 🆕 mới | Render `duynhlab.conf` upstream block từ `services.yaml` |
| `scripts/build-rpm.sh` | ✅ rewrite | rpmbuild local hoặc mock chroot |
| `scripts/smoke-install.sh` | ✅ giữ | Adjust: 1 RPM thay vì 11 |
| `scripts/fetch-sources.sh` | ✅ giữ | Clone 9 service repos |
| `packaging/common/scripts/duynhlab-{ctl,db-setup,gen-password,gen-env}` | ✅ giữ + thêm `gen-env` | Ship vào `/opt/duynhlab/lib/` |
| `packaging/rpm/lib/init-service.sh` | 🆕 mới | Idempotent migrator (xem MOCM `init-service.sh`) |
| `packaging/rpm/lib/password-generator.sh` | 🆕 mới | Generate `/etc/opt/duynhlab/*.env` từ tpl |
| `packaging/rpm/secret-tpl/<svc>.env.tpl` | 🆕 mới | 9 file (8 backend + frontend) |
| `packaging/rpm/nginx/duynhlab.conf` | ✅ rewrite | Full reverse proxy (8 upstream) thay vì chỉ frontend |
| `packaging/rpm/valkey/duynhlab.conf` | 🆕 mới | Tuning snippet |
| `packaging/rpm/postgresql/{duynhlab-tuning.conf,bootstrap.sql}` | 🆕 mới | DB tuning + user/DB bootstrap |
| `packaging/rpm/logrotate/duynhlab-{services,nginx}` | 🆕 mới | Logrotate configs |

### 4.3 Cleanup files cần xoá (sau Phase S4)

```
packaging/rpm/nfpm.tmpl.yaml
packaging/rpm/nfpm-common.tmpl.yaml
packaging/rpm/nfpm-frontend.tmpl.yaml
packaging/rpm/nfpm-platform.tmpl.yaml
packaging/rpm/scriptlets/*.tmpl
packaging/rpm/scriptlets/common-*.sh
packaging/rpm/scriptlets/frontend-*.sh
scripts/render-nfpm.sh
scripts/build-common.sh
scripts/stage-rpm.sh
scripts/stage-frontend.sh
```

### 4.4 Makefile (rewrite)

```make
.PHONY: help fetch-sources build-local-all stage build smoke clean

VERSION ?= $(shell date +%Y.%m.%d)

help:
	@echo "make fetch-sources       # clone 9 service repos"
	@echo "make build-local-all     # build 9 binaries from sibling checkouts"
	@echo "make stage               # stage all into build/staging/ + tarball"
	@echo "make build               # rpmbuild local (default)"
	@echo "make build BUILD_RUNNER=mock"
	@echo "make smoke               # dnf install + verify in Rocky 9"
	@echo "make all                 # build-local-all + stage + build + smoke"
	@echo "make clean"

fetch-sources:
	./scripts/fetch-sources.sh

build-local-all:
	for s in auth user product cart order review notification shipping frontend; do \
	  DUYNHLAB_NO_GIT=1 ./scripts/build-local.sh $$s; \
	done

stage:
	VERSION=$(VERSION) ./scripts/stage-all.sh

build: stage
	VERSION=$(VERSION) BUILD_RUNNER=$${BUILD_RUNNER:-rpmbuild} ./scripts/build-rpm.sh

smoke:
	./scripts/smoke-install.sh

all: build-local-all build smoke

clean:
	rm -rf build/ dist/
```

### 4.5 CI workflow

`.github/workflows/build.yml`:

```yaml
name: Build RPM
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:
    inputs: { ref: { default: main } }

jobs:
  build:
    runs-on: ubuntu-24.04
    container:
      image: fedora:42
      options: --privileged
    steps:
      - uses: actions/checkout@v4
        with: { path: packages }
      - run: dnf -y install mock rpm-build createrepo_c go nodejs npm yq jq git
      - run: packages/scripts/fetch-sources.sh
      - run: |
          cd packages
          for s in auth user product cart order review notification shipping frontend; do
            DUYNHLAB_NO_GIT=1 ./scripts/build-local.sh $s
          done
      - run: cd packages && make stage
      - run: cd packages && BUILD_RUNNER=mock ./scripts/build-rpm.sh
      - run: cd packages && CONTAINER_RUNNER=docker ./scripts/smoke-install.sh
      - uses: actions/upload-artifact@v4
        with:
          name: rpms
          path: packages/dist/*.rpm
          retention-days: 14
```

### 4.6 Publish (Phase S5)

Adapt từ TON:

`.github/workflows/publish-yum-repo.yml`:

```yaml
on:
  workflow_run:
    workflows: ["Build RPM"]
    types: [completed]
    branches: [main]

jobs:
  publish:
    if: github.event.workflow_run.conclusion == 'success'
    runs-on: ubuntu-24.04
    container: { image: rockylinux:9 }
    steps:
      - run: dnf -y install createrepo_c rpm-sign git
      - uses: actions/download-artifact@v4
        with: { name: rpms, path: dist }
      - uses: actions/checkout@v4
        with: { ref: gh-pages, path: pages }
      - run: |
          mkdir -p pages/rpm/el9/x86_64
          cp dist/*.rpm pages/rpm/el9/x86_64/
          # GPG sign (Phase S5)
          # rpm --addsign pages/rpm/el9/x86_64/*.rpm
          createrepo_c pages/rpm/el9/x86_64/
          cd pages && git add . && git commit -m "publish $(date +%F)" && git push
```

User repo `.repo`:

```ini
[duynhlab]
name=duynhlab platform
baseurl=https://duynhlab.github.io/packages/rpm/el9/$basearch
enabled=1
gpgcheck=1
gpgkey=https://duynhlab.github.io/packages/RPM-GPG-KEY-duynhlab
```

---

## 5. Migration roadmap

### Phase S0 — Spike (1 ngày) ⏳
- [ ] Tạo `specs/duynhlab.spec` v0 (skeleton từ §3, hardcode 1-2 service).
- [ ] Manually tạo `build/staging/` từ output Phase 1 hiện tại.
- [ ] `tar czf duynhlab-2026.05.20-staging.tar.gz staging/`.
- [ ] `rpmbuild -ba specs/duynhlab.spec --define "_sourcedir $PWD/build/sources"`.
- [ ] Inspect: `rpm -qlp`, `rpm -qip`, `rpm -q --scripts`, `rpm -qd`, `rpm -qc`.
- [ ] Install vào Rocky 9 container, assert layout = §2.2.
- [ ] Check `%autorelease` available trên fedora:42 + EL9 (cần `epel-release` + `rpmautospec-rpm-macros`).
- [ ] Decision check: monorepo size OK? (~80MB RPM, ~150MB installed)

### Phase S1 — Skeleton đầy đủ (3-4 ngày)
- [ ] Viết `scripts/stage-all.sh` (orchestrate stage 9 services + libs + configs).
- [ ] Viết `scripts/render-systemd.sh` (8 backend `.service` + 2 `.target` từ `services.yaml`).
- [ ] Viết `scripts/render-nginx.sh` (upstream block 8 backend).
- [ ] Viết `packaging/rpm/lib/init-service.sh` (port từ MOCM, simplify).
- [ ] Viết `packaging/rpm/lib/password-generator.sh` (loop 9 services, render tpl, idempotent).
- [ ] Viết 9 `packaging/rpm/secret-tpl/<svc>.env.tpl`.
- [ ] Viết `packaging/rpm/nginx/duynhlab.conf` + `valkey/duynhlab.conf` + `postgresql/{tuning.conf,bootstrap.sql}` + `logrotate/duynhlab-*`.
- [ ] Viết `packaging/common/scripts/duynhlab-gen-env`.
- [ ] Hoàn thiện `specs/duynhlab.spec` v1 (full 9 service).
- [ ] `make all` chạy local — pass.

### Phase S2 — Mock CI (1-2 ngày)
- [ ] `BUILD_RUNNER=mock` chạy local OK trên `fedora:42` container.
- [ ] Update `.github/workflows/build.yml` sang mock-based pipeline.
- [ ] Add `rpmlint` step (warning-only ban đầu).
- [ ] Matrix `rocky-9-x86_64` + `alma-9-x86_64`.
- [ ] Upload `*.rpm` + `*.src.rpm` artifact.

### Phase S3 — Full systemd smoke (2 ngày)
- [ ] `scripts/smoke-install.sh` mở rộng: dùng `quay.io/centos/centos:stream9-init` + `--systemd=true`, sidecar `postgres:16`, `valkey/valkey:8`, `nginx:1.26`.
- [ ] Chạy `duynhlab-db-setup bootstrap` + `migrate` + `systemctl start duynhlab-platform.target` + `curl http://localhost/health`.
- [ ] Verify D21: reinstall preserve env, uninstall preserve `/etc/opt/duynhlab/` + DB.
- [ ] Verify upgrade flow: install v1 → bump version → install v2 → service restart, env preserved.

### Phase S4 — Cleanup nFPM (0.5 ngày)
- [ ] Xoá files §4.3.
- [ ] Update `AGENTS.md`: "Packaging tool: rpmbuild + mock".
- [ ] Update `plan.md`: mark Phase 1.2 obsolete, link sang plan-spec.md.

### Phase S5 — Distribution + hardening (2-3 ngày)
- [ ] `gh-pages` branch + `publish-yum-repo.yml` (pattern TON).
- [ ] GPG key generation, secret, `rpm --addsign`.
- [ ] `RPM-GPG-KEY-duynhlab` ship trên Pages.
- [ ] User-facing doc: `docs/install.md` với `.repo` snippet.
- [ ] `rpmlint` zero-warning gate.
- [ ] Optional: aarch64 mock cross-build.

**Tổng: ~9-12 ngày (1 dev).**

---

## 6. Risk + Mitigation

| Risk | Khả năng | Tác động | Mitigation |
|---|---|---|---|
| RPM 80MB quá lớn, mỗi service bump → rebuild full | Cao | Trung bình | Acceptable trade-off của monorepo. Mitigate bằng zstd compression (default), incremental upgrade chỉ tốn delta băng thông qua `dnf` deltarpm (optional). |
| Version skew: 1 service release v0.2, các service khác v0.1 → toàn bộ bump | Cao | Cao | Mega-RPM design intentionally couples versions. Nếu cần độc lập sau này, split lại theo Option Hybrid. Cho giai đoạn POC/early-prod: chấp nhận. |
| `%ghost` env conflict với postinstall write | Trung bình | Thấp | Verified pattern MOCM; `rpm -V` không complain. |
| `init-service.sh` ghi `/etc/nginx/conf.d/` xung đột admin config | Trung bình | Trung bình | Chỉ copy nếu file chưa tồn tại. Admin biết và document trong `docs/install.md`. |
| `valkey` chưa có trên Rocky 9.0-9.3 | Trung bình | Trung bình | `Requires: (valkey or redis)`. Smoke test default Rocky 9.4. |
| `%autorelease` không có | Trung bình | Trung bình | EL9 cần `epel-release` + `rpmautospec-rpm-macros`. Fallback: hardcode `Release: 1%{?dist}`. |
| Mock cần `--privileged` | Cao | Thấp | Đã verified Fedora container option. |
| Go debuginfo strip fail | Cao | Thấp | `%global debug_package %{nil}` đã include. |
| Port-conflict check trong `%pre` block install không hợp lý | Cao | Trung bình | MOCM dùng pattern này (block port 30000s). Cho duynhlab: chỉ check trên FIRST install, optional skip qua `--define "_skip_port_check 1"`. |
| Migration from nFPM RPM → SPEC RPM (existing prod) | Thấp (chưa prod) | Cao | Tên RPM khác (`duynhlab-platform` meta cũ vs `duynhlab` mới). Cần `dnf remove duynhlab-* && dnf install duynhlab`. Document trong `docs/migration.md`. |

---

## 7. So sánh: 11 RPM (nFPM hiện tại) vs 1 RPM (SPEC mới)

| Khía cạnh | 11 RPM nFPM | 1 RPM SPEC (mega) |
|---|---|---|
| File count | 11 RPM | 1 RPM |
| Install command | `dnf install duynhlab-platform` (pull deps) | `dnf install duynhlab` |
| Per-service upgrade | `dnf upgrade duynhlab-auth` chỉ rebuild auth | Phải upgrade full mega-RPM |
| Disk size | ~80MB tổng | ~80MB (same) |
| Build time | 11× nFPM ~5s = 55s | 1× rpmbuild ~30s |
| Scriptlet code | Duplicate 8 lần (postinstall.sh per backend) | 1 chỗ trong SPEC |
| Service team ownership | Mỗi service repo có thể own RPM riêng (deferred) | Tất cả ship cùng |
| Version sync | Mỗi RPM version riêng | Cùng version |
| Spec file complexity | 11 file YAML đơn giản | 1 file SPEC ~400 dòng |
| Match release-driven (Phase 1.1) | ✅ phù hợp | ❌ couples versions |
| Match user request | ❌ | ✅ user chọn Option A |

User đã chọn Option A (mega-RPM) → release-driven coupling chấp nhận được cho giai đoạn này.

---

## 8. Open follow-up (sau khi S0 spike xong)

1. **Frontend systemd unit?** — Hiện đề xuất KHÔNG (nginx serve trực tiếp dist). Cần xác nhận với FE team.
2. **`/var/log/duynhlab/` vs journald only?** — MOCM ship `StandardOutput=append:/var/log/...`. duynhlab plan.md hiện nói "journald only". Quyết định: giữ journald (simpler, logrotate-free).
3. **Valkey vs Redis** — Default Recommend valkey. Có cần fallback redis runtime?
4. **PG version**: Require `postgresql >= 14`, nhưng PG18 sắp release (2025-09). Có cần `>= 16`?
5. **Backup/restore tool**: Có ship `duynhlab-backup` vào mega-RPM không? (Hiện không có)
6. **TLS/cert generation**: MOCM có `tls-generate.sh`. duynhlab có cần?

---

## 9. Inspiration credit

- **MOCM** (`Opswat/mem-devops/docker-rpm-build`): mega-RPM pattern, init-service.sh idempotent migrator, secret-tpl + password-generator, systemd target taxonomy.
- **ton-blockchain/packages**: repack-only SPEC, createrepo_c + gh-pages, multi-arch dir layout.
- **Fedora Golang Guidelines**: `%global debug_package %{nil}` cho Go, `%systemd_*` macros, `%autorelease`/`%autochangelog`.
