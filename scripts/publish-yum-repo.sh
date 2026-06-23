#!/usr/bin/env bash
# scripts/publish-yum-repo.sh — assemble the gh-pages YUM repo tree.
#
# Produces under $REPO_OUT (default build/gh-pages):
#   rpm/el9/x86_64/repodata/repomd.xml   (createrepo_c metadata)
#   duynhlab.repo, index.html, README.md, .nojekyll   (static, from packages/pages/)
#
# Two modes:
#   LOCAL    (default)              — copy dist/*.rpm into the tree, index them
#                                     with relative hrefs → a self-contained,
#                                     servable repo for `make publish-repo`.
#   RELEASE  (RPM_TREE set)         — RPMs live as GitHub Release assets; only the
#                                     repodata is published. createrepo_c writes
#                                     absolute <location href> via --location-prefix
#                                     so gh-pages never holds an .rpm (no 100 MB
#                                     git-file limit, no history bloat). RPM_TREE is
#                                     a dir of per-tag subdirs (v<tag>/*.rpm) whose
#                                     relative paths are preserved → the repodata
#                                     indexes several versions (dnf downgrade works).
#                                     Requires RELEASE_BASE_URL (release-assets root).
#
# Runner ($CREATEREPO_RUNNER): host | podman | docker (auto via pick_runner).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

REPO_OUT="${REPO_OUT:-$BUILD_DIR/gh-pages}"
RPM_SRC="${RPM_SRC:-$DIST_DIR}"
ARCH_DIR="rpm/el9/x86_64"
PAGES_SRC="$REPO_ROOT/packages/pages"
RPM_TREE="${RPM_TREE:-}"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-}"

ARCH_OUT="$REPO_OUT/$ARCH_DIR"
mkdir -p "$ARCH_OUT"

# ── Stage createrepo_c input + flags per mode ──────────────────────────────────
shopt -s nullglob
cr_args=()
if [[ -n "$RPM_TREE" ]]; then
  # RELEASE: index the per-tag tree in a scratch dir; RPMs served from releases.
  [[ -n "$RELEASE_BASE_URL" ]] || die "RPM_TREE requires RELEASE_BASE_URL (release-assets root)"
  [[ "$RELEASE_BASE_URL" == */ ]] || RELEASE_BASE_URL="$RELEASE_BASE_URL/"
  rpms=( "$RPM_TREE"/*/*.x86_64.rpm "$RPM_TREE"/*/*.noarch.rpm )
  [[ ${#rpms[@]} -gt 0 ]] || die "No RPMs under $RPM_TREE/<tag>/"
  CR_INPUT="$BUILD_DIR/createrepo-input"
  rm -rf "$CR_INPUT"; mkdir -p "$CR_INPUT"
  cp -a "$RPM_TREE/." "$CR_INPUT/"        # preserve v<tag>/ → relative part of each href
  cr_args=( --location-prefix "$RELEASE_BASE_URL" )
  log_info "RELEASE mode — ${#rpms[@]} RPM(s) across $(ls -1 "$RPM_TREE" | wc -l) version dir(s), served from $RELEASE_BASE_URL"
else
  # LOCAL: copy the flat dist RPMs into the published arch dir, index in place.
  rpms=( "$RPM_SRC"/*.x86_64.rpm "$RPM_SRC"/*.noarch.rpm )
  [[ ${#rpms[@]} -gt 0 ]] || die "No RPMs in $RPM_SRC — run scripts/build-rpm.sh first"
  CR_INPUT="$ARCH_OUT"
  for r in "${rpms[@]}"; do cp -f "$r" "$CR_INPUT/"; done
  log_info "LOCAL mode — ${#rpms[@]} RPM(s) copied into $CR_INPUT"
fi
# SRPMs are intentionally not published (exceed GitHub's 100 MB file limit, and
# `dnf install` of a binary repo never needs them).

# ── createrepo_c ───────────────────────────────────────────────────────────────
runner="$(pick_runner createrepo_c "${CREATEREPO_RUNNER:-}")"
log_step "createrepo_c (runner=$runner)"
case "$runner" in
  host)
    createrepo_c "${cr_args[@]}" "$CR_INPUT"
    ;;
  podman|docker)
    sel=""; [[ "$runner" == "podman" ]] && sel=":Z"
    "$runner" run --rm \
      -v "$CR_INPUT:/cr_input${sel}" \
      -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
      rockylinux:9 bash -c '
        set -e
        command -v createrepo_c >/dev/null 2>&1 \
          || dnf -y install --setopt=install_weak_deps=False createrepo_c >/dev/null
        createrepo_c '"${cr_args[*]}"' /cr_input
        chown -R "${HOST_UID}:${HOST_GID}" /cr_input/repodata 2>/dev/null || true
      '
    ;;
esac

# In RELEASE mode the arch dir must stay .rpm-free: publish only the fresh
# repodata (replacing any stale metadata / leftover RPMs from a prior checkout).
if [[ -n "$RPM_TREE" ]]; then
  rm -f "$ARCH_OUT"/*.rpm
  rm -rf "$ARCH_OUT/repodata"
  cp -rf "$CR_INPUT/repodata" "$ARCH_OUT/repodata"
  # Rootless podman can leave subuid-owned scratch files; never fail the publish.
  rm -rf "$CR_INPUT" 2>/dev/null \
    || log_warn "could not fully clean $CR_INPUT (container-owned files) — continuing"
fi
log_ok "repodata: $ARCH_OUT/repodata/repomd.xml"

# ── Static landing files (root of gh-pages) ────────────────────────────────────
cp -a "$PAGES_SRC/." "$REPO_OUT/"
log_ok "landing: $(cd "$PAGES_SRC" && ls | tr '\n' ' ')"

log_info "Final tree:"
( cd "$REPO_OUT" && find rpm -maxdepth 4 -type f | sort | head -30 ) >&2
log_ok "YUM repo staged at $REPO_OUT (base https://duynhlab.github.io/packages)"
