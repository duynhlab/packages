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

# RELEASE_BASE_URL — when set, RPM payloads live as GitHub Release assets and
# only the repodata is published to gh-pages. createrepo_c writes absolute
# <location href> entries pointing at the release download URL, so the gh-pages
# arch dir never holds an .rpm (avoids the 100 MB git file limit + history bloat).
# Must end with a trailing slash, e.g.
#   https://github.com/duynhlab/packages/releases/download/v2026.06.04/
# When unset, the script falls back to the local model (RPMs copied into the
# tree) so `make publish-repo` still produces a self-contained, servable repo.
RELEASE_BASE_URL="${RELEASE_BASE_URL:-}"

# RPM_TREE — multi-version release mode. A directory of per-tag subdirs, e.g.
#   $RPM_TREE/v2026.06.10/duynhlab-2026.06.10-1.el9.x86_64.rpm
#   $RPM_TREE/v2026.06.11/duynhlab-2026.06.11-1.el9.x86_64.rpm
# The tree is indexed as-is: createrepo_c preserves the relative paths, so with
#   RELEASE_BASE_URL=https://github.com/<owner>/<repo>/releases/download/
# every <location href> resolves to that version's own Release asset. This lets
# the repodata index several versions at once (dnf downgrade works). Requires
# RELEASE_BASE_URL. Mutually exclusive with the flat RPM_SRC model.
RPM_TREE="${RPM_TREE:-}"

shopt -s nullglob
if [[ -n "$RPM_TREE" ]]; then
  [[ -n "$RELEASE_BASE_URL" ]] || die "RPM_TREE requires RELEASE_BASE_URL (release-assets root)"
  rpms=( "$RPM_TREE"/*/*.x86_64.rpm "$RPM_TREE"/*/*.noarch.rpm )
  [[ ${#rpms[@]} -gt 0 ]] || die "No RPMs under $RPM_TREE/<tag>/"
  log_info "RPM_TREE=$RPM_TREE  (${#rpms[@]} files across $(ls -1 "$RPM_TREE" | wc -l) version dirs)"
else
  rpms=( "$RPM_SRC"/*.x86_64.rpm "$RPM_SRC"/*.noarch.rpm )
  [[ ${#rpms[@]} -gt 0 ]] || die "No RPMs in $RPM_SRC — run scripts/build-rpm.sh first"
  log_info "RPM_SRC=$RPM_SRC  (${#rpms[@]} files)"
fi
log_info "REPO_OUT=$REPO_OUT"

# createrepo_c always runs over a self-contained input dir holding the RPMs.
# In release mode that's a scratch dir (RPMs discarded after metadata is built);
# in local mode it's the published arch dir itself.
mkdir -p "$REPO_OUT/$ARCH_DIR"
if [[ -n "$RELEASE_BASE_URL" ]]; then
  [[ "$RELEASE_BASE_URL" == */ ]] || RELEASE_BASE_URL="$RELEASE_BASE_URL/"
  CR_INPUT="$BUILD_DIR/createrepo-input"
  rm -rf "$CR_INPUT"; mkdir -p "$CR_INPUT"
  log_info "RELEASE mode — RPMs served from $RELEASE_BASE_URL"
else
  CR_INPUT="$REPO_OUT/$ARCH_DIR"
  log_info "LOCAL mode — RPMs copied into $CR_INPUT"
fi

if [[ -n "$RPM_TREE" ]]; then
  # Preserve the v<tag>/ subdirs — they become the relative part of each href.
  cp -a "$RPM_TREE/." "$CR_INPUT/"
else
  for r in "${rpms[@]}"; do
    cp -f "$r" "$CR_INPUT/"
  done
fi
log_ok "staged ${#rpms[@]} RPM(s) into $CR_INPUT"

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

# In release mode createrepo runs fresh on a scratch dir (no prior repodata),
# so --update is a no-op there; in local mode --update reuses cached checksums.
cr_args=( --update )
[[ -n "$RELEASE_BASE_URL" ]] && cr_args=( --location-prefix "$RELEASE_BASE_URL" )

run_host_createrepo() {
  createrepo_c "${cr_args[@]}" "$CR_INPUT"
}

run_container_createrepo() {
  local rt=$1 sel=""
  [[ "$rt" == "podman" ]] && sel=":Z"
  "$rt" run --rm \
    -v "$CR_INPUT:/cr_input${sel}" \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -w / \
    rockylinux:9 \
    bash -c '
      set -e
      if ! command -v createrepo_c >/dev/null 2>&1; then
        dnf -y install --setopt=install_weak_deps=False createrepo_c >/dev/null
      fi
      createrepo_c '"${cr_args[*]}"' /cr_input
      chown -R "${HOST_UID}:${HOST_GID}" /cr_input/repodata 2>/dev/null || true
    '
}

case "$runner" in
  host)            run_host_createrepo ;;
  podman|docker)   run_container_createrepo "$runner" ;;
  *) die "Unknown CREATEREPO_RUNNER: $runner" ;;
esac

# In release mode, move only the freshly built repodata into the published tree
# (replace any stale repodata; the arch dir must stay .rpm-free, so also purge
# any leftover RPMs from an earlier accumulator-branch checkout).
if [[ -n "$RELEASE_BASE_URL" ]]; then
  rm -f "$REPO_OUT/$ARCH_DIR"/*.rpm
  rm -rf "$REPO_OUT/$ARCH_DIR/repodata"
  mkdir -p "$REPO_OUT/$ARCH_DIR"
  cp -rf "$CR_INPUT/repodata" "$REPO_OUT/$ARCH_DIR/repodata"
  # Scratch cleanup must never fail the publish (rootless podman can leave
  # subuid-owned files behind that the invoking user cannot remove).
  rm -rf "$CR_INPUT" 2>/dev/null \
    || log_warn "could not fully clean $CR_INPUT (container-owned files) — continuing"
fi

log_ok "repodata generated: $REPO_OUT/$ARCH_DIR/repodata/repomd.xml"

# Link used on the landing page's "Browse" list. In tree mode RELEASE_BASE_URL
# is the bare releases/download/ root (not browsable) — link the Releases page.
if [[ -n "$RPM_TREE" ]]; then
  RELEASE_LINK="${RELEASE_BASE_URL%releases/download/}releases"
elif [[ -n "$RELEASE_BASE_URL" ]]; then
  RELEASE_LINK="$RELEASE_BASE_URL"
else
  RELEASE_LINK="rpm/el9/x86_64/"
fi

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
<pre>for svc in auth user product cart order review notification shipping; do
  SUPERUSER_DSN="postgresql://postgres:secret@localhost:5432/postgres" \\
    sudo -E duynhlab-db-setup bootstrap "\$svc"
  sudo duynhlab-db-setup migrate "\$svc"
done
sudo systemctl enable --now duynhlab-platform.target</pre>

<h2>Browse</h2>
<ul>
  <li><a href="$RELEASE_LINK">RPM downloads (GitHub Releases)</a></li>
  <li><a href="rpm/el9/x86_64/repodata/">rpm/el9/x86_64/repodata/</a> (metadata)</li>
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

See [\`docs/002-install.md\`](https://github.com/duynhlab/packages/blob/main/docs/002-install.md)
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
