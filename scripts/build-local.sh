#!/usr/bin/env bash
# scripts/build-local.sh — Phase 1.0 (D22): build a service from a sibling
# checkout under $DUYNHLAB_SRC_ROOT (default: ../) and stage tarballs into
# build/<service>/raw/, mimicking what fetch-release.sh will produce in CI.
#
# Usage: build-local.sh <service> [version]
#   - Reads services.yaml for repo / binary / build_path / migrations
#   - cd $DUYNHLAB_SRC_ROOT/<src_dir>
#   - git fetch && checkout main && pull --ff-only (unless DUYNHLAB_NO_GIT=1)
#   - go build (CGO=0, GOOS=linux GOARCH=amd64)
#   - tar -> build/<svc>/raw/<binary>-<ver>-linux-amd64.tar.gz
#   - SHA256 alongside the tarball
#   - Migrations are embedded in the binary (//go:embed) — NOT tarred (D24). The
#     highest migration version is recorded in build-info.env as SCHEMA_VERSION (audit).
#   - Frontend (type=static): bake build.env (VITE_*) then npm ci && npm run build
#     -> frontend-dist.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat >&2 <<EOF
Usage: $0 <service> [version]

Arguments:
  service   Service name from services.yaml (e.g. auth, user, frontend)
  version   Optional semver/tag for filename (default: 0.0.0-local+<git-sha>)

Environment:
  DUYNHLAB_SRC_ROOT  Sibling repos root      (default: $DUYNHLAB_SRC_ROOT)
  DUYNHLAB_NO_GIT=1  Skip git fetch/checkout (use working tree as-is)
  GOOS GOARCH        Override target         (default: linux amd64)
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
SERVICE=$1
VERSION=${2:-}

svc_exists "$SERVICE" || die "Service '$SERVICE' not in services.yaml"

require_cmd git tar
GOOS=${GOOS:-linux}
GOARCH=${GOARCH:-amd64}

# ── Resolve service metadata ─────────────────────────────────────────────────
SRC_DIR=$(svc_field "$SERVICE" src_dir)
TYPE=$(svc_field "$SERVICE" type)
BINARY=$(svc_field "$SERVICE" binary)
BUILD_PATH=$(svc_field "$SERVICE" build_path)
SRC_PATH="$DUYNHLAB_SRC_ROOT/$SRC_DIR"

[[ -d "$SRC_PATH" ]] || die "Source directory not found: $SRC_PATH (set DUYNHLAB_SRC_ROOT)"

log_step "Service:    $SERVICE ($TYPE)"
log_step "Source:     $SRC_PATH"

# ── git sync ─────────────────────────────────────────────────────────────────
if [[ "${DUYNHLAB_NO_GIT:-0}" != "1" ]]; then
  log_step "git fetch + checkout main + pull --ff-only"
  ( cd "$SRC_PATH"
    if ! git diff --quiet || ! git diff --cached --quiet; then
      die "Working tree dirty in $SRC_PATH (commit/stash or set DUYNHLAB_NO_GIT=1)"
    fi
    git fetch --tags --prune origin
    git checkout main
    git pull --ff-only origin main
  )
else
  log_warn "DUYNHLAB_NO_GIT=1 — using working tree as-is"
fi

# ── Resolve version ──────────────────────────────────────────────────────────
GIT_SHA=$(cd "$SRC_PATH" && git rev-parse --short HEAD)
if [[ -z "$VERSION" ]]; then
  VERSION="0.0.0-local+${GIT_SHA}"
fi
log_step "Version:    $VERSION (sha=$GIT_SHA)"

# ── Output dir ───────────────────────────────────────────────────────────────
RAW_DIR="$BUILD_DIR/$SERVICE/raw"
rm -rf "$RAW_DIR"
mkdir -p "$RAW_DIR"

# ── Build phase ──────────────────────────────────────────────────────────────
case "$TYPE" in
  backend)
    require_cmd go
    [[ -n "$BINARY" ]]     || die "binary not set for $SERVICE"
    [[ -n "$BUILD_PATH" ]] || die "build_path not set for $SERVICE"

    log_step "go build $BUILD_PATH -> $BINARY ($GOOS/$GOARCH)"
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT

    mkdir -p "$STAGE/bin"
    ( cd "$SRC_PATH"
      CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" \
      GOTOOLCHAIN="${GOTOOLCHAIN:-auto}" \
        go build -trimpath -ldflags="-s -w -X main.version=$VERSION" \
        -o "$STAGE/bin/$BINARY" "$BUILD_PATH"
    )
    [[ -x "$STAGE/bin/$BINARY" ]] || die "Build did not produce $STAGE/bin/$BINARY"

    for f in LICENSE README.md; do
      [[ -f "$SRC_PATH/$f" ]] && cp "$SRC_PATH/$f" "$STAGE/" || true
    done

    TARBALL="$RAW_DIR/${BINARY}-${VERSION}-${GOOS}-${GOARCH}.tar.gz"
    tar -czf "$TARBALL" -C "$STAGE" .
    sha256_of "$TARBALL" > "${TARBALL}.sha256"
    log_ok "Binary tarball: ${TARBALL#$REPO_ROOT/} ($(du -h "$TARBALL" | cut -f1), sha256=$(cut -c1-12 < "${TARBALL}.sha256"))"

    # Migrations are embedded in the binary (//go:embed); we do NOT ship loose SQL.
    # Record the highest migration version for audit (SCHEMA_VERSION in build-info.env).
    MIG_SRC="$SRC_PATH/db/migrations/sql"
    if [[ -d "$MIG_SRC" ]] && compgen -G "$MIG_SRC/*.up.sql" >/dev/null; then
      SCHEMA_VERSION=$(for f in "$MIG_SRC"/*.up.sql; do basename "$f" | cut -d_ -f1; done \
        | sed 's/^0*//' | sort -n | tail -1)
      SCHEMA_VERSION=${SCHEMA_VERSION:-0}
      log_ok "Migrations:     embedded in binary, max version=$SCHEMA_VERSION ($(ls "$MIG_SRC"/*.up.sql | wc -l) up-files)"
    else
      log_warn "No migrations dir ($MIG_SRC) — SCHEMA_VERSION unset"
    fi
    ;;

  static)
    require_cmd npm
    # Bake build-time env (e.g. VITE_API_BASE_URL) from services.yaml .build.env.
    # Vite inlines these at build time — they cannot be changed at runtime.
    BUILD_ENV=()
    while IFS= read -r kv; do
      [[ -z "$kv" ]] && continue
      BUILD_ENV+=("$kv")
      log_step "build env: $kv"
    done < <(svc_build_env "$SERVICE")

    log_step "npm ci && npm run build -> dist/"
    STAGE=$(mktemp -d)
    trap 'rm -rf "$STAGE"' EXIT

    ( cd "$SRC_PATH"
      npm ci
      env ${BUILD_ENV[@]+"${BUILD_ENV[@]}"} npm run build
    )

    # Find build output (vite=dist, next=.next or out, cra=build)
    OUT=""
    for cand in dist build out .next/standalone; do
      if [[ -d "$SRC_PATH/$cand" ]]; then OUT="$SRC_PATH/$cand"; break; fi
    done
    [[ -n "$OUT" ]] || die "Cannot locate frontend build output (tried dist/build/out/.next/standalone)"
    log_step "Output dir: ${OUT#$SRC_PATH/}"

    TARBALL="$RAW_DIR/frontend-${VERSION}-dist.tar.gz"
    tar -czf "$TARBALL" -C "$(dirname "$OUT")" "$(basename "$OUT")"
    sha256_of "$TARBALL" > "${TARBALL}.sha256"
    log_ok "Frontend tarball: ${TARBALL#$REPO_ROOT/} ($(du -h "$TARBALL" | cut -f1))"
    ;;

  *)
    die "Unknown service type: $TYPE"
    ;;
esac

# ── Metadata sidecar (consumed by build-rpm.sh later) ────────────────────────
cat > "$RAW_DIR/build-info.env" <<EOF
SERVICE=$SERVICE
TYPE=$TYPE
VERSION=$VERSION
GIT_SHA=$GIT_SHA
GOOS=$GOOS
GOARCH=$GOARCH
SCHEMA_VERSION=${SCHEMA_VERSION:-}
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SOURCE=local
EOF

log_ok "Done. Artifacts in: ${RAW_DIR#$REPO_ROOT/}"
ls -1 "$RAW_DIR" | sed 's/^/  - /' >&2
