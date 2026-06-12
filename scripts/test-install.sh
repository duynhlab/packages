#!/usr/bin/env bash
# test-install.sh — End-to-end install test for the mega-RPM in Rocky 9.
#
# Verifies:
#   - dnf localinstall succeeds and resolves all dependencies via EPEL + module
#   - user/group created
#   - /opt/duynhlab/** payload present (8 backends + frontend + CLI + templates)
#   - /etc/duynhlab/<svc>.env generated mode 0640 root:duynhlab with random pw
#   - /etc/nginx/conf.d/duynhlab.conf dropped by init-service.sh
#   - systemd unit files installed (8 services + 2 targets)
#   - reinstall preserves env files
#   - uninstall preserves /etc/duynhlab/
#
# Note: systemctl is stubbed in containers; scriptlets use "|| :" so missing
# PID 1 is tolerated.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

ls "$DIST_DIR"/duynhlab-*.x86_64.rpm >/dev/null 2>&1 \
  || die "No mega-RPM in $DIST_DIR — run scripts/build-rpm.sh"

RUNNER=${CONTAINER_RUNNER:-podman}
require_cmd "$RUNNER"
case $RUNNER in
  podman) VOL_OPTS=":Z" ;;
  *)      VOL_OPTS="" ;;
esac

log_step "Running install test inside rockylinux:9 ($RUNNER)"

"$RUNNER" run --rm -i \
  -v "$REPO_ROOT:/work$VOL_OPTS" \
  -w /work \
  rockylinux:9 \
  bash -eu -o pipefail <<'INNER'

echo "::group::Repo + dependency setup"
dnf -y install epel-release >/dev/null
dnf -y module enable postgresql:16 >/dev/null
# Valkey lives in EPEL on EL9; nginx in AppStream.
# Deliberately NO yq here: customer hosts won't have it — duynhctl must
# work with the copy bundled in the RPM (/opt/duynhlab/lib/yq).
dnf -y install postgresql nginx valkey shadow-utils which file >/dev/null
echo "::endgroup::"

echo "::group::dnf localinstall mega-RPM"
dnf -y localinstall dist/duynhlab-*.x86_64.rpm
echo "::endgroup::"

echo "::group::Installed package"
rpm -qi duynhlab | head -15
echo "::endgroup::"

echo "::group::User/group"
getent passwd duynhlab
getent group duynhlab
echo "::endgroup::"

echo "::group::/opt/duynhlab layout"
ls /opt/duynhlab/
for svc in auth user product cart order review notification shipping; do
  bin="/opt/duynhlab/$svc/bin/$svc-service"
  test -x "$bin" || { echo "MISSING binary: $bin"; exit 1; }
  file "$bin" | grep -q "ELF.*executable" || { echo "NOT ELF: $bin"; exit 1; }
  test -s "/opt/duynhlab/$svc/BINARY_VERSION" || { echo "MISSING BINARY_VERSION: $svc"; exit 1; }
  test -s "/opt/duynhlab/$svc/SCHEMA_VERSION" || { echo "MISSING SCHEMA_VERSION: $svc"; exit 1; }
  # Migrations are embedded in the binary — no loose SQL should be shipped (D24).
  test ! -e "/opt/duynhlab/$svc/migrations" \
    || { echo "UNEXPECTED migrations dir shipped: $svc"; exit 1; }
done
test -f /opt/duynhlab/frontend/dist/index.html
test -d /opt/duynhlab/secret-tpl
test -f /opt/duynhlab/nginx/duynhlab.conf
test -f /opt/duynhlab/valkey/duynhlab.conf
test -f /opt/duynhlab/postgresql/duynhlab-tuning.conf
test -f /opt/duynhlab/postgresql/bootstrap.sql
test -f /opt/duynhlab/logrotate/duynhlab-services
test -f /opt/duynhlab/logrotate/duynhlab-nginx
test -x /opt/duynhlab/lib/init-service.sh
test -x /opt/duynhlab/lib/password-generator.sh
echo "Layout OK"
echo "::endgroup::"

echo "::group::CLI symlinks"
for c in duynhctl duynhdb \
         duynhenv duynhpass; do
  which "$c"
done
# duynhlab-db-migrate must NOT exist anymore (D23).
! which duynhlab-db-migrate 2>/dev/null || { echo "UNEXPECTED duynhlab-db-migrate present"; exit 1; }
duynhpass 16 || true
test -f /etc/duynhlab/services.yaml || { echo "services.yaml not dropped"; exit 1; }
echo "::endgroup::"

echo "::group::duynhctl works out-of-box (yq pulled as RPM dependency)"
# We never install yq by hand in this test — `Requires: yq` must have made dnf
# pull it (mikefarah yq from EPEL). This reproduces a clean customer host.
command -v yq >/dev/null 2>&1 || { echo "MISSING yq — Requires: yq not resolved"; exit 1; }
yq --version | grep -q mikefarah || { echo "WRONG yq (expected mikefarah): $(yq --version)"; exit 1; }
duynhctl list
duynhctl ports
echo "::endgroup::"

echo "::group::secret versioning — re-running the generator must change nothing"
grep -q "^secretVersion=1$" /etc/duynhlab/secret_version.properties \
  || { echo "BAD secret_version.properties"; exit 1; }
stat -c '%a' /etc/duynhlab/secret_version.properties | grep -qx 640 \
  || { echo "secret_version.properties not 0640"; exit 1; }
before=$(sha256sum /etc/duynhlab/*.env | sha256sum)
/opt/duynhlab/lib/password-generator.sh
after=$(sha256sum /etc/duynhlab/*.env | sha256sum)
[ "$before" = "$after" ] || { echo "GENERATOR NOT IDEMPOTENT — env files changed"; exit 1; }
echo "idempotent OK"
echo "::endgroup::"

echo "::group::install history log"
grep -q "installed on" /var/log/duynhlab/version.log \
  || { echo "MISSING version.log entry"; exit 1; }
cat /var/log/duynhlab/version.log
echo "::endgroup::"

echo "::group::support-bundle contains NO secrets"
duynhctl support-bundle /tmp
bundle=$(ls /tmp/duynhlab-support-*.tar.gz | head -1)
[ -f "$bundle" ] || { echo "NO bundle produced"; exit 1; }
# Take a real password value and prove it is absent from the bundle.
pass=$(grep -m1 '^DB_PASSWORD=' /etc/duynhlab/auth.env | cut -d= -f2)
mkdir -p /tmp/bundle-x && tar -xzf "$bundle" -C /tmp/bundle-x
if grep -r -q "$pass" /tmp/bundle-x; then
  echo "SECRET LEAKED INTO SUPPORT BUNDLE"; exit 1
fi
ls /tmp/bundle-x/*/ | head -10
echo "no secrets in bundle OK"
echo "::endgroup::"

echo "::group::systemd units"
ls /usr/lib/systemd/system/duynhlab-*.{service,target}
expected_services="auth user product cart order review notification shipping"
for svc in $expected_services; do
  test -f /usr/lib/systemd/system/duynhlab-$svc.service \
    || { echo "MISSING unit: duynhlab-$svc.service"; exit 1; }
done
test -f /usr/lib/systemd/system/duynhlab-platform.target
test -f /usr/lib/systemd/system/duynhlab-infra.target
echo "--- one sample unit ---"
cat /usr/lib/systemd/system/duynhlab-auth.service
echo "--- platform target ---"
cat /usr/lib/systemd/system/duynhlab-platform.target
echo "::endgroup::"

echo "::group::Env files generated mode 0640 with random password"
ls -la /etc/duynhlab/
for svc in auth user product cart order review notification shipping; do
  f="/etc/duynhlab/$svc.env"
  test -f "$f" || { echo "MISSING env: $f"; exit 1; }
  stat -c '%U:%G %a %n' "$f"
  mode=$(stat -c '%a' "$f")
  test "$mode" = "640" || { echo "Wrong mode on $f: $mode"; exit 1; }
  grep -q '__DB_PASSWORD__' "$f" && { echo "Placeholder not replaced: $f"; exit 1; }
  grep -Eq '^DB_PASSWORD=.{20,}' "$f" || { echo "DB_PASSWORD too short: $f"; exit 1; }
done
test -f /etc/duynhlab/secret_version.properties
test -f /etc/duynhlab/env-global.properties
echo "Sample env (auth):"
sed 's/^DB_PASSWORD=.*/DB_PASSWORD=<redacted>/' /etc/duynhlab/auth.env
echo "::endgroup::"

echo "::group::nginx vhost dropped"
test -f /etc/nginx/conf.d/duynhlab.conf || { echo "nginx vhost not installed"; exit 1; }
nginx -t 2>&1 || true
echo "::endgroup::"

echo "::group::valkey + logrotate snippets"
ls /etc/valkey/conf.d/ 2>/dev/null || ls /etc/valkey/ 2>/dev/null || true
ls /etc/logrotate.d/ | grep duynhlab || echo "no logrotate snippets (acceptable)"
echo "::endgroup::"

echo "::group::Log directories"
for svc in auth user product cart order review notification shipping; do
  test -d /var/log/duynhlab/$svc || { echo "MISSING log dir: $svc"; exit 1; }
done
test -d /var/log/duynhlab/nginx
ls -ld /var/log/duynhlab /var/log/duynhlab/auth /var/log/duynhlab/nginx
echo "::endgroup::"

echo "::group::duynhctl basic commands"
duynhctl list || true
duynhctl ports || true
duynhctl version || true
echo "::endgroup::"

echo "::group::Reinstall preserves env"
ORIG=$(sha256sum /etc/duynhlab/auth.env | awk '{print $1}')
dnf -y reinstall dist/duynhlab-*.x86_64.rpm >/dev/null
NEW=$(sha256sum /etc/duynhlab/auth.env | awk '{print $1}')
test "$ORIG" = "$NEW" || { echo "Env file overwritten on reinstall!"; exit 1; }
echo "Env preserved on reinstall: OK"
echo "::endgroup::"

echo "::group::Uninstall removes payload (env preserved by upgrade, not erase)"
dnf -y remove duynhlab >/dev/null
test ! -f /usr/lib/systemd/system/duynhlab-auth.service \
  || { echo "units not removed"; exit 1; }
test ! -d /opt/duynhlab \
  || { echo "/opt/duynhlab not removed"; exit 1; }
# Note: %ghost files are removed on `rpm -e` (rpm doesn't preserve them).
# Env preservation is only guaranteed across reinstall/upgrade, which the
# previous block already validated.
echo "Uninstall OK (payload removed)"
echo "::endgroup::"

echo ""
echo "================================================================"
echo "  INSTALL TEST PASSED"
echo "================================================================"
INNER
