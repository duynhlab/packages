#!/usr/bin/env bash
# fetch-sources.sh — Clone every service repo from services.yaml into
# $DUYNHLAB_SRC_ROOT (default: ../) so build-local.sh can compile them.
#
# Usage: scripts/fetch-sources.sh [ref]
#   ref   git ref to check out (default: main)
#
# Re-running the script updates existing clones:
#   * git fetch + git checkout <ref>
#   * if ref looks like a branch, also `git pull --ff-only`.

set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_cmd git

REF=${1:-main}
mkdir -p "$DUYNHLAB_SRC_ROOT"

while read -r svc; do
  [[ -n $svc ]] || continue
  repo=$(svc_field "$svc" repo)
  src_dir=$(svc_field "$svc" src_dir)
  dest="$DUYNHLAB_SRC_ROOT/$src_dir"

  if [[ -d $dest/.git ]]; then
    log_step "Updating $repo -> $dest ($REF)"
    git -C "$dest" fetch --tags --prune origin
    git -C "$dest" checkout "$REF"
    if git -C "$dest" symbolic-ref -q HEAD >/dev/null; then
      git -C "$dest" pull --ff-only origin "$REF"
    fi
  else
    log_step "Cloning $repo -> $dest ($REF)"
    git clone --depth 50 --branch "$REF" "https://github.com/${repo}.git" "$dest"
  fi
done < <(svc_list)

log_ok "Sources ready under $DUYNHLAB_SRC_ROOT"
