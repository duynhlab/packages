#!/usr/bin/env bash
# fetch-releases.sh — Download released BACKEND binaries from each service's
# GitHub Release (GoReleaser) and stage them into build/<svc>/raw/ in EXACTLY
# the shape build-local.sh produces, so scripts/stage-all.sh consumes them
# unchanged. This is the "consume the release instead of compiling" path; the
# source path lives in fetch-sources.sh + build-local.sh.
#
# Usage: scripts/fetch-releases.sh [lock-file]
#   lock-file   per-service version pins (default: <repo>/services.lock).
#               Lines "<svc>=<tag>" (e.g. auth=v1.0.0); '#' comments allowed.
#               A service with no pin (or "=latest") resolves to its newest
#               non-draft release.
#
# Only `type=backend` services are handled here. The frontend has no binary
# release (it ships a container image) — it stays on fetch-sources.sh +
# build-local.sh (static/npm) and is skipped here.
#
# Requires: gh (authenticated; GH_TOKEN in CI), tar, sha256sum/shasum.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_cmd gh tar

LOCK_FILE=${1:-"$REPO_ROOT/services.lock"}

# pinned_tag <svc> — echo the tag pinned in the lock file, or "" if unset.
pinned_tag() {
  local svc=$1
  [[ -f "$LOCK_FILE" ]] || { printf ''; return; }
  # last match wins; ignore comments/blanks; trim spaces
  awk -F= -v s="$svc" '
    /^[[:space:]]*#/ { next }
    { gsub(/[[:space:]]/, "") }
    $1 == s { v = $2 }
    END { print v }
  ' "$LOCK_FILE"
}

# resolve_tag <svc> <repo> — the lock pin, or the latest non-draft release tag.
resolve_tag() {
  local svc=$1 repo=$2 tag
  tag=$(pinned_tag "$svc")
  if [[ -z "$tag" || "$tag" == "latest" ]]; then
    tag=$(gh release view --repo "$repo" --json tagName -q .tagName) \
      || die "No releases found for $repo (and no pin in $LOCK_FILE)"
  fi
  printf '%s\n' "$tag"
}

# verify_sha256 <dir> <tarball-basename> — check <tarball>.sha256 (GoReleaser
# split-checksum format "<hash>  <name>"); fall back to a manual hash compare.
verify_sha256() {
  local dir=$1 tgz=$2 sumfile="$2.sha256"
  ( cd "$dir"
    [[ -f "$sumfile" ]] || die "Missing checksum $sumfile for $tgz"
    if ! sha256sum -c "$sumfile" >/dev/null 2>&1; then
      # Some producers write only the bare hash — compare manually.
      local want got
      want=$(awk '{print $1}' "$sumfile")
      got=$(sha256_of "$tgz")
      [[ "$want" == "$got" ]] || die "Checksum mismatch for $tgz (want $want, got $got)"
    fi
  )
  log_ok "checksum verified: $tgz"
}

fetch_one() {
  local svc=$1
  local repo binary tag tmp rel_tgz stage raw_dir out_tgz ver
  repo=$(svc_field "$svc" repo)
  binary=$(svc_field "$svc" binary)
  [[ -n "$binary" ]] || die "binary not set for $svc"

  tag=$(resolve_tag "$svc" "$repo")
  log_step "Fetching $repo release $tag -> $svc"

  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  gh release download "$tag" --repo "$repo" --dir "$tmp" \
    --pattern "${binary}-*-linux-amd64.tar.gz" \
    --pattern "${binary}-*-linux-amd64.tar.gz.sha256" \
    --pattern "build-info.env" \
    || die "Failed to download $repo@$tag assets"

  rel_tgz=$(basename "$(ls "$tmp/${binary}"-*-linux-amd64.tar.gz | head -1)")
  [[ -n "$rel_tgz" ]] || die "No binary tarball in $repo@$tag"
  [[ -f "$tmp/build-info.env" ]] || die "No build-info.env asset in $repo@$tag"

  verify_sha256 "$tmp" "$rel_tgz"

  # Normalise layout: the release tarball's first path component is bin/<binary>
  # (no leading ./), but stage-all.sh extracts with --strip-components=1 expecting
  # build-local.sh's "./bin/..." shape. Re-tar via a staging dir so stage-all
  # stays byte-for-byte unchanged.
  stage=$(mktemp -d)
  tar -xzf "$tmp/$rel_tgz" -C "$stage"
  [[ -x "$stage/bin/$binary" ]] || die "Release tarball missing bin/$binary"

  raw_dir="$BUILD_DIR/$svc/raw"
  rm -rf "$raw_dir"; mkdir -p "$raw_dir"

  ver=$(. "$tmp/build-info.env"; printf '%s' "${VERSION:-${tag#v}}")
  out_tgz="$raw_dir/${binary}-${ver}-linux-amd64.tar.gz"
  tar -czf "$out_tgz" -C "$stage" .
  sha256_of "$out_tgz" > "$out_tgz.sha256"
  cp "$tmp/build-info.env" "$raw_dir/build-info.env"
  rm -rf "$stage"

  log_ok "staged $svc from release ($rel_tgz, version $ver)"
}

while read -r svc; do
  [[ -n $svc ]] || continue
  [[ "$(svc_field "$svc" type)" == "backend" ]] || continue
  fetch_one "$svc"
done < <(svc_list)

log_ok "Backend release binaries ready under $BUILD_DIR/*/raw"
