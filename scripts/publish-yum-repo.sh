#!/usr/bin/env bash
# scripts/publish-yum-repo.sh — assemble a YUM repo tree from dist/*.rpm.
#
# Produces:
#   $REPO_OUT/rpm/el9/x86_64/*.rpm
#   $REPO_OUT/rpm/el9/x86_64/repodata/repomd.xml
#   $REPO_OUT/index.html, README.md, duynhlab.repo
#
# Defaults:
#   REPO_OUT=build/gh-pages
#   RPM_SRC=dist
#
# In CI, gh-pages branch is checked out into $REPO_OUT first so this script
# only overwrites the rpm/ tree and root landing files.
#
# Runner selection ($CREATEREPO_RUNNER): host | podman | docker (auto).
# Container image used when no host createrepo_c: rockylinux:9.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

REPO_OUT="${REPO_OUT:-$BUILD_DIR/gh-pages}"
RPM_SRC="${RPM_SRC:-$DIST_DIR}"
ARCH_DIR="rpm/el9/x86_64"
BASE_URL="${BASE_URL:-https://duynhlab.github.io/packages}"
PAGES_HOST="${PAGES_HOST:-duynhlab.github.io}"

shopt -s nullglob
rpms=( "$RPM_SRC"/*.x86_64.rpm "$RPM_SRC"/*.noarch.rpm )
[[ ${#rpms[@]} -gt 0 ]] || die "No RPMs in $RPM_SRC — run scripts/build-rpm.sh first"

log_info "RPM_SRC=$RPM_SRC  (${#rpms[@]} files)"
log_info "REPO_OUT=$REPO_OUT"

mkdir -p "$REPO_OUT/$ARCH_DIR"

# Copy fresh RPMs in (overwrite — same NVRA produces identical bits).
for r in "${rpms[@]}"; do
  cp -f "$r" "$REPO_OUT/$ARCH_DIR/"
done
log_ok "copied ${#rpms[@]} RPM(s) into $REPO_OUT/$ARCH_DIR"

# SRPMs are intentionally NOT published: the .src.rpm exceeds GitHub's 100 MB
# per-file limit and is not needed for `dnf install` of a binary repo.

# ── createrepo_c ──────────────────────────────────────────────────────────────
runner="${CREATEREPO_RUNNER:-}"
if [[ -z "$runner" ]]; then
  if command -v createrepo_c >/dev/null 2>&1; then
    runner=host
  elif command -v podman >/dev/null 2>&1; then
    runner=podman
  elif command -v docker >/dev/null 2>&1; then
    runner=docker
  else
    die "No createrepo_c on host and no podman/docker available"
  fi
fi

log_step "createrepo_c (runner=$runner)"

run_host_createrepo() {
  createrepo_c --update "$REPO_OUT/$ARCH_DIR"
}

run_container_createrepo() {
  local rt=$1 sel=""
  [[ "$rt" == "podman" ]] && sel=":Z"
  "$rt" run --rm \
    -v "$REPO_OUT:/repo${sel}" \
    -w /repo \
    rockylinux:9 \
    bash -c '
      set -e
      if ! command -v createrepo_c >/dev/null 2>&1; then
        dnf -y install --setopt=install_weak_deps=False createrepo_c >/dev/null
      fi
      createrepo_c --update '"$ARCH_DIR"'
    '
}

case "$runner" in
  host)            run_host_createrepo ;;
  podman|docker)   run_container_createrepo "$runner" ;;
  *) die "Unknown CREATEREPO_RUNNER: $runner" ;;
esac

log_ok "repodata generated: $REPO_OUT/$ARCH_DIR/repodata/repomd.xml"

# ── Landing files (root of gh-pages) ──────────────────────────────────────────
cat > "$REPO_OUT/duynhlab.repo" <<EOF
[duynhlab]
name=duynhlab platform packages (EL\$releasever)
baseurl=$BASE_URL/rpm/el\$releasever/\$basearch/
enabled=1
gpgcheck=0
repo_gpgcheck=0
EOF

cat > "$REPO_OUT/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>duynhlab packages</title>
<style>body{font-family:system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 16px;color:#222}code,pre{background:#f4f4f4;padding:2px 6px;border-radius:4px}pre{padding:12px;overflow:auto}</style>
<h1>duynhlab packages</h1>
<p>YUM repository for the <strong>duynhlab</strong> e-commerce platform.
Hosted on GitHub Pages, backed by the
<a href="https://github.com/duynhlab/packages">duynhlab/packages</a> repository.</p>

<h2>Install (Rocky / Alma / RHEL 9)</h2>
<pre>sudo curl -fsSL -o /etc/yum.repos.d/duynhlab.repo $BASE_URL/duynhlab.repo
sudo dnf install -y duynhlab</pre>

<h2>Bootstrap</h2>
<pre>SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \\
  sudo -E duynhlab-db-setup bootstrap
sudo duynhlab-db-setup migrate
sudo systemctl enable --now duynhlab-platform.target</pre>

<h2>Browse</h2>
<ul>
  <li><a href="rpm/el9/x86_64/">rpm/el9/x86_64/</a></li>
  <li><a href="duynhlab.repo">duynhlab.repo</a></li>
</ul>
EOF

cat > "$REPO_OUT/README.md" <<EOF
# duynhlab packages — YUM repository

Hosted at <$BASE_URL>.

\`\`\`bash
sudo curl -fsSL -o /etc/yum.repos.d/duynhlab.repo $BASE_URL/duynhlab.repo
sudo dnf install -y duynhlab
\`\`\`

See [\`docs/install.md\`](https://github.com/duynhlab/packages/blob/main/docs/install.md)
for the full guide.
EOF

cat > "$REPO_OUT/.nojekyll" <<EOF
EOF

log_ok "wrote duynhlab.repo, index.html, README.md, .nojekyll"

# ── Summary ───────────────────────────────────────────────────────────────────
log_info "Final tree:"
( cd "$REPO_OUT" && find rpm -maxdepth 4 -type f | sort | head -30 ) >&2

cat <<EOF

================================================================
  YUM repo staged at: $REPO_OUT
  Base URL:           $BASE_URL
  Test locally:
    python3 -m http.server -d $REPO_OUT 8080 &
    cat > /tmp/duynhlab.repo <<'REPO'
[duynhlab-local]
name=duynhlab local
baseurl=http://localhost:8080/rpm/el9/\$basearch/
enabled=1
gpgcheck=0
REPO
================================================================
EOF
