%global duynhlab_user    duynhlab
%global duynhlab_group   duynhlab
%global duynhlab_prefix  /opt/duynhlab
%global duynhlab_etc     /etc/duynhlab
%global duynhlab_log     /var/log/duynhlab
%global duynhlab_state   /var/lib/duynhlab

# Go binaries are already stripped — debuginfo extraction does not work.
%global debug_package %{nil}

# Don't try to mangle shebangs in shipped helper scripts that live under /opt.
%global __brp_mangle_shebangs_exclude_from %{duynhlab_prefix}/lib/.*\.sh$

# Avoid auto-Requires from random ELF symbols inside shipped Go binaries
# (they statically link everything they need).
%global __requires_exclude ^(libc\\.so|libpthread\\.so).*$
%global __provides_exclude_from %{duynhlab_prefix}/.*

Name:           duynhlab
Version:        %{?_duynhlab_version}%{!?_duynhlab_version:2026.05.20}
Release:        1%{?dist}
Summary:        duynhlab e-commerce platform (mega-RPM)
License:        Proprietary
URL:            https://duynhlab.github.io/packages
Vendor:         duynhlab
Packager:       duynhlab ops <ops@duynhlab.io>

Source0:        duynhlab-%{version}-staging.tar.gz

BuildArch:      x86_64

BuildRequires:  systemd-rpm-macros
BuildRequires:  coreutils
BuildRequires:  tar

Requires:       systemd
Requires:       bash >= 4.0
Requires:       coreutils
Requires:       nginx >= 1.20
Requires:       postgresql >= 14
Requires:       (valkey >= 7.2 or redis >= 6)
# mikefarah yq (EPEL ≥4.47 on EL9) — duynhlab-ctl parses services.yaml with it.
# EPEL is already a documented prerequisite (valkey lives there too).
Requires:       yq >= 4
Requires(pre):  shadow-utils
Requires(pre):  /usr/bin/getent
%{?systemd_requires}

Recommends:     nginx >= 1.24
Recommends:     valkey >= 8
Recommends:     postgresql-server >= 16
Recommends:     logrotate

%description
duynhlab e-commerce platform — single mega-RPM containing:

  * 8 Go backend services (auth, user, product, cart, order, review,
    notification, shipping) under /opt/duynhlab/<svc>/bin/
  * Frontend SPA (static dist) under /opt/duynhlab/frontend/dist/
  * CLI tools: duynhlab-ctl, duynhlab-db-setup, duynhlab-gen-env,
    duynhlab-gen-password
  * Per-service systemd units + duynhlab-platform.target + duynhlab-infra.target
  * Template configs for nginx, valkey, postgresql, logrotate
  * Idempotent init-service.sh that drops configs into /etc/ on first install
  * Random password generation on first install (preserved on upgrade)

Install:  dnf install duynhlab
Bootstrap: duynhlab-db-setup bootstrap <svc> && duynhlab-db-setup migrate <svc>
           (migrate runs the service binary's own embedded migrations)
Start:    systemctl enable --now duynhlab-platform.target

%prep
%setup -q -c -T -n duynhlab-%{version}
tar -xzf %{S:0} --strip-components=0

%build
# Nothing to compile — all binaries pre-built by upstream service repos.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}%{duynhlab_prefix}
mkdir -p %{buildroot}%{_unitdir}
mkdir -p %{buildroot}%{_bindir}
mkdir -p %{buildroot}%{duynhlab_etc}

# 1. /opt/duynhlab/** — main payload (8 services + frontend + lib + templates)
cp -a opt/duynhlab/. %{buildroot}%{duynhlab_prefix}/

# 2. systemd units
cp -a systemd/. %{buildroot}%{_unitdir}/

# 3. /usr/bin symlinks to /opt/duynhlab/lib/* CLI tools
for tool in duynhlab-ctl duynhlab-db-setup \
            duynhlab-gen-env duynhlab-gen-password; do
  ln -sf %{duynhlab_prefix}/lib/$tool %{buildroot}%{_bindir}/$tool
done

# 4. Bash completion (optional, ship if exists)
if [ -f opt/duynhlab/lib/duynhlab-ctl.bash-completion ]; then
  install -Dm 0644 opt/duynhlab/lib/duynhlab-ctl.bash-completion \
    %{buildroot}%{_datadir}/bash-completion/completions/duynhlab-ctl
fi

%check
# Sanity: every backend binary must exist and be ELF.
for svc in auth user product cart order review notification shipping; do
  bin="%{buildroot}%{duynhlab_prefix}/${svc}/bin/${svc}-service"
  test -x "$bin" || { echo "MISSING: $bin"; exit 1; }
  file "$bin" | grep -q "ELF.*executable" || { echo "NOT-ELF: $bin"; exit 1; }
done

# Frontend index.html must exist.
test -f %{buildroot}%{duynhlab_prefix}/frontend/dist/index.html

# Lib scripts must be executable.
for sh in init-service.sh password-generator.sh; do
  test -x "%{buildroot}%{duynhlab_prefix}/lib/${sh}" || { echo "missing $sh"; exit 1; }
done

%pre
# On upgrade ($1 == 2): stop platform target so binaries can be replaced.
if [ $1 -gt 1 ]; then
  systemctl stop duynhlab-platform.target >/dev/null 2>&1 || :
fi

# Create user/group (idempotent).
getent group %{duynhlab_group} >/dev/null || \
  groupadd -r %{duynhlab_group}
getent passwd %{duynhlab_user} >/dev/null || \
  useradd -r -g %{duynhlab_group} -d %{duynhlab_prefix} -s /sbin/nologin \
    -c "duynhlab platform service account" %{duynhlab_user}

exit 0

%post
# 1. Drop config templates, create log dirs, fix permissions.
if [ -x %{duynhlab_prefix}/lib/init-service.sh ]; then
  %{duynhlab_prefix}/lib/init-service.sh || :
fi

# 2. On first install only: generate env files with random passwords.
if [ $1 -eq 1 ]; then
  if [ -x %{duynhlab_prefix}/lib/password-generator.sh ]; then
    %{duynhlab_prefix}/lib/password-generator.sh || :
  fi
fi

# 3. systemd_post for every shipped unit.
%systemd_post duynhlab-platform.target
%systemd_post duynhlab-infra.target
for svc in auth user product cart order review notification shipping; do
  if [ -f %{_unitdir}/duynhlab-${svc}.service ]; then
    /usr/bin/systemctl preset duynhlab-${svc}.service >/dev/null 2>&1 || :
  fi
done

# 4. Reload nginx if it is already running (config dropped by init-service.sh).
if systemctl is-active --quiet nginx 2>/dev/null; then
  nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || :
fi

# 5. First-install hint.
if [ $1 -eq 1 ]; then
cat <<'EOF'

================================================================
  duynhlab installed.

  Next steps (as root), per backend service (auth user product cart
  order review notification shipping):

    # 1. Bootstrap PostgreSQL (one-time, per service):
    SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \
      duynhlab-db-setup bootstrap auth

    # 2. Run migrations (runs the service binary's embedded migrations):
    duynhlab-db-setup migrate auth

    # 3. Start platform:
    systemctl enable --now duynhlab-platform.target

    # 4. Verify:
    duynhlab-ctl status
    curl http://localhost/health
================================================================
EOF
fi

exit 0

%preun
# Remove ($1 == 0) — stop + disable everything cleanly.
if [ $1 -eq 0 ]; then
  systemctl stop duynhlab-platform.target >/dev/null 2>&1 || :
  systemctl disable duynhlab-platform.target >/dev/null 2>&1 || :
  for svc in auth user product cart order review notification shipping; do
    %systemd_preun duynhlab-${svc}.service
  done
  %systemd_preun duynhlab-platform.target
  %systemd_preun duynhlab-infra.target
fi
exit 0

%postun
# Upgrade ($1 == 1): restart services so the new binary takes over.
if [ $1 -eq 1 ]; then
  for svc in auth user product cart order review notification shipping; do
    %systemd_postun_with_restart duynhlab-${svc}.service
  done
fi
# Remove ($1 == 0): KEEP /etc/duynhlab/ (env+passwords) and the DB.
exit 0

%files
%defattr(-,root,root,-)

# Payload tree
%dir %attr(0755, root, root) %{duynhlab_prefix}
%{duynhlab_prefix}/auth
%{duynhlab_prefix}/user
%{duynhlab_prefix}/product
%{duynhlab_prefix}/cart
%{duynhlab_prefix}/order
%{duynhlab_prefix}/review
%{duynhlab_prefix}/notification
%{duynhlab_prefix}/shipping
%{duynhlab_prefix}/frontend
%{duynhlab_prefix}/etc
%{duynhlab_prefix}/nginx
%{duynhlab_prefix}/valkey
%{duynhlab_prefix}/postgresql
%{duynhlab_prefix}/secret-tpl
%{duynhlab_prefix}/logrotate
%{duynhlab_prefix}/lib

# /usr/bin symlinks
%{_bindir}/duynhlab-ctl
%{_bindir}/duynhlab-db-setup
%{_bindir}/duynhlab-gen-env
%{_bindir}/duynhlab-gen-password

# Optional bash completion
%{_datadir}/bash-completion/completions/duynhlab-ctl

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

# /etc/duynhlab — managed by init-service.sh + password-generator.sh
%dir %attr(0755, root, %{duynhlab_group}) %{duynhlab_etc}
%ghost %attr(0644, root, root)            %{duynhlab_etc}/services.yaml
%ghost %attr(0644, root, root)            %{duynhlab_etc}/env-global.properties
%ghost %attr(0644, root, root)            %{duynhlab_etc}/secret_version.properties
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/auth.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/user.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/product.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/cart.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/order.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/review.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/notification.env
%ghost %attr(0640, root, %{duynhlab_group}) %{duynhlab_etc}/shipping.env

%changelog
* Sun May 24 2026 duynhlab ops <ops@duynhlab.io> - 2026.05.20-1
- Initial mega-RPM release (Option A monorepo SPEC).
- 8 backend services + frontend + common CLI in a single package.
- Inspired by Opswat MOCM packaging pattern.
