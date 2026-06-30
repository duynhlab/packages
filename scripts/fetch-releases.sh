#!/usr/bin/env bash
# fetch-releases.sh — Download released BACKEND binaries from each service's
# GitHub Release (GoReleaser) and extract them into build/<svc>/raw/payload/ in
# EXACTLY the shape build-local.sh produces, so scripts/stage-all.sh consumes
# both modes unchanged. This is the "consume the release instead of compiling"
# path; the source path lives in fetch-sources.sh + build-local.sh.
#
# Usage: scripts/fetch-releases.sh
#   Resolves each backend's LATEST non-draft GitHub Release (same org) — no pin
#   file. Bump a service by cutting a new release tag in its repo.
#
# Only `type=backend` services are handled here. The frontend has no binary
# release (it ships a container image) — it stays on fetch-sources.sh +
# build-local.sh (static/npm) and is skipped here.
#
# Requires: gh (authenticated; GH_TOKEN in CI), tar, sha256sum/shasum.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_cmd gh tar

# resolve_tag <repo> — the latest non-draft release tag for the repo.
resolve_tag() {
  local repo=$1 tag
  tag=$(gh release view --repo "$repo" --json tagName -q .tagName) \
    || die "No releases found for $repo"
  printf '%s\n' "$tag"
}

# verify_checksums <dir> — verify the downloaded tarball against the combined
# checksums.txt (GoReleaser standard layout). --ignore-missing checks only the
# files actually present in the dir (i.e. the one tarball we downloaded).
verify_checksums() {
  local dir=$1
  ( cd "$dir"
    [[ -f checksums.txt ]] || die "Missing checksums.txt"
    sha256sum --ignore-missing -c checksums.txt >/dev/null 2>&1 \
      || die "Checksum mismatch against checksums.txt"
  )
  log_ok "checksum verified (checksums.txt)"
}

fetch_one() {
  local svc=$1
  local repo binary tag tmp rel_tgz raw_dir
  repo=$(svc_field "$svc" repo)
  binary=$(svc_field "$svc" binary)
  [[ -n "$binary" ]] || die "binary not set for $svc"

  tag=$(resolve_tag "$repo")
  log_step "Fetching $repo release $tag -> $svc"

  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  gh release download "$tag" --repo "$repo" --dir "$tmp" \
    --pattern "${binary}-*-linux-amd64.tar.gz" \
    --pattern "checksums.txt" \
    || die "Failed to download $repo@$tag assets"

  rel_tgz=$(basename "$(ls "$tmp/${binary}"-*-linux-amd64.tar.gz | head -1)")
  [[ -n "$rel_tgz" ]] || die "No binary tarball in $repo@$tag"

  verify_checksums "$tmp"

  # Extract straight into raw/payload/ — the same shape build-local.sh stages,
  # so stage-all.sh copies both modes identically (no re-tar, no strip-components).
  raw_dir="$BUILD_DIR/$svc/raw"
  rm -rf "$raw_dir"; mkdir -p "$raw_dir/payload"
  tar -xzf "$tmp/$rel_tgz" -C "$raw_dir/payload"
  [[ -x "$raw_dir/payload/bin/$binary" ]] || die "Release tarball missing bin/$binary"
  printf '%s\n' "${tag#v}" > "$raw_dir/VERSION"

  log_ok "staged $svc from release ($rel_tgz, ${tag#v})"
}

while read -r svc; do
  [[ -n $svc ]] || continue
  [[ "$(svc_field "$svc" type)" == "backend" ]] || continue
  fetch_one "$svc"
done < <(svc_list)

log_ok "Backend release binaries ready under $BUILD_DIR/*/raw"
