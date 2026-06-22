#!/usr/bin/env bash
# scripts/build-rpm.sh — build duynhlab mega-RPM.
#
# Runs rpmbuild against packages/rpm/duynhlab.spec using:
#   $BUILD_DIR/sources/duynhlab-${VERSION}-staging.tar.gz   (produced by stage-all.sh)
#
# Runner selection ($BUILD_RUNNER):
#   host    — use the host rpmbuild (rpm-build package required)
#   podman  — run inside rockylinux:9 container (default if host lacks rpmbuild)
#   docker  — same as podman, with docker
#
# Output: dist/duynhlab-${VERSION}-1.el9.x86_64.rpm
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VERSION="${VERSION:-$(date -u +%Y.%m.%d)}"
SPEC="$REPO_ROOT/packages/rpm/duynhlab.spec"
SRC="$BUILD_DIR/sources/duynhlab-${VERSION}-staging.tar.gz"
TOP="$BUILD_DIR/rpmbuild"

[[ -f "$SPEC" ]] || die "Missing $SPEC"
[[ -f "$SRC"  ]] || die "Missing $SRC — run scripts/stage-all.sh first"

BUILD_RUNNER="$(pick_runner rpmbuild "${BUILD_RUNNER:-}")"

log_info "VERSION=$VERSION  RUNNER=$BUILD_RUNNER"
mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$DIST_DIR"

run_host_build() {
  rpmbuild -ba "$SPEC" \
    --define "_topdir $TOP" \
    --define "_sourcedir $BUILD_DIR/sources" \
    --define "_duynhlab_version $VERSION"
}

run_container_build() {
  local runtime=$1
  local image="${BUILD_IMAGE:-rockylinux:9}"
  log_step "running rpmbuild in $runtime container ($image)"

  local sel=""
  [[ "$runtime" == "podman" ]] && sel=":Z"

  $runtime run --rm \
    -v "$REPO_ROOT:/workspace${sel}" \
    -w /workspace \
    -e VERSION="$VERSION" \
    "$image" \
    bash -c '
      set -e
      if ! command -v rpmbuild >/dev/null 2>&1; then
        echo "[INFO] installing rpm-build + systemd-rpm-macros"
        dnf -y install --setopt=install_weak_deps=False rpm-build systemd-rpm-macros file >/dev/null
      fi
      mkdir -p build/rpmbuild/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
      rpmbuild -ba packages/rpm/duynhlab.spec \
        --define "_topdir /workspace/build/rpmbuild" \
        --define "_sourcedir /workspace/build/sources" \
        --define "_duynhlab_version ${VERSION}"
    '
}

case "$BUILD_RUNNER" in
  host)            run_host_build ;;
  podman|docker)   run_container_build "$BUILD_RUNNER" ;;
  *) die "Unknown BUILD_RUNNER: $BUILD_RUNNER" ;;
esac

# ── Collect output ────────────────────────────────────────────────────────────
# Scope to the version just built: rpmbuild never cleans RPMS/ SRPMS/, so an
# unscoped glob would also copy stale RPMs from earlier builds into dist/.
shopt -s nullglob
rpms=( "$TOP/RPMS/x86_64/duynhlab-${VERSION}-"*.rpm )
srpms=( "$TOP/SRPMS/duynhlab-${VERSION}-"*.src.rpm )
[[ ${#rpms[@]} -gt 0 ]] || die "rpmbuild produced no x86_64 RPM for $VERSION"

for r in "${rpms[@]}" "${srpms[@]}"; do
  cp -f "$r" "$DIST_DIR/"
  log_ok "$(basename "$r") -> dist/"
done

log_info "ARTIFACTS:"
ls -lh "$DIST_DIR"/duynhlab-*.rpm 2>/dev/null | awk '{print "  "$5"  "$9}' >&2
