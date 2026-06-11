# duynhlab/packages — RPM SPEC mega-package builder
#
# Option A: single monorepo SPEC at specs/duynhlab.spec produces ONE RPM
# (duynhlab-<VERSION>-1.el9.x86_64.rpm) containing all 8 backends + frontend
# + CLI tools + nginx/valkey/postgresql config templates.

.PHONY: help all fetch-sources build-local build-local-all render-systemd \
        stage build test-install test-integration publish-repo release clean

SERVICE          ?=
VERSION          ?= $(shell date -u +%Y.%m.%d)
DUYNHLAB_SRC_ROOT ?= $(abspath ..)

export VERSION
export DUYNHLAB_SRC_ROOT

help:
	@echo "duynhlab/packages — RPM SPEC pipeline (mega-RPM)"
	@echo ""
	@echo "  fetch-sources [REF=main]   Clone every service repo into \$$DUYNHLAB_SRC_ROOT"
	@echo "  build-local SERVICE=<name> Build one service from sibling checkout"
	@echo "  build-local-all            Build every service in services.yaml"
	@echo "  render-systemd             Render unit + target files (build/staging/systemd/)"
	@echo "  stage                      Assemble the Source0 staging tarball"
	@echo "  build                      Run rpmbuild (host or container) -> dist/"
	@echo "  test-install               Install dist/*.rpm in Rocky 9 + verify"
	@echo "  test-integration           Boot platform: podman --systemd=always + Postgres sidecar"
	@echo "  publish-repo               Stage gh-pages YUM repo (build/gh-pages/)"
	@echo "  release                    Cut a release: next CalVer tag (vYYYY.MM.DD[.N]) -> push -> CI publishes"
	@echo "  all                        stage + build + test-install"
	@echo "  clean                      Remove build/ and dist/"
	@echo ""
	@echo "Environment:"
	@echo "  VERSION=$(VERSION)"
	@echo "  DUYNHLAB_SRC_ROOT=$(DUYNHLAB_SRC_ROOT)"
	@echo "  BUILD_RUNNER=host|podman|docker  (auto)"

fetch-sources:
	@bash scripts/fetch-sources.sh $(REF)

build-local:
	@test -n "$(SERVICE)" || (echo "ERROR: SERVICE= required"; exit 1)
	@bash scripts/build-local.sh $(SERVICE) $(VERSION)

build-local-all:
	@for s in $$(yq '.services[].name' services.yaml); do \
	  echo "--- build-local $$s ---"; \
	  bash scripts/build-local.sh $$s || exit 1; \
	done

render-systemd:
	@bash scripts/render-systemd.sh

stage:
	@bash scripts/stage-all.sh

build: stage
	@bash scripts/build-rpm.sh

test-install:
	@bash scripts/test-install.sh

test-integration:
	@bash scripts/test-integration.sh

publish-repo:
	@bash scripts/publish-yum-repo.sh

# Cut a release. Computes the next free CalVer tag for today (v2026.06.11,
# then v2026.06.11.1, ...), creates an ANNOTATED tag on main and pushes it —
# .github/workflows/release.yml does the rest (build, test, publish).
release:
	@set -e; \
	branch=$$(git branch --show-current); \
	[ "$$branch" = "main" ] || { echo "ERROR: release from main only (on $$branch)"; exit 1; }; \
	git diff --quiet && git diff --cached --quiet || { echo "ERROR: working tree dirty"; exit 1; }; \
	git fetch -q --tags origin main; \
	[ "$$(git rev-parse HEAD)" = "$$(git rev-parse origin/main)" ] || { echo "ERROR: main not up to date with origin (git pull first)"; exit 1; }; \
	base="v$$(date -u +%Y.%m.%d)"; tag="$$base"; n=0; \
	while git rev-parse -q --verify "refs/tags/$$tag" >/dev/null; do \
	  n=$$((n+1)); tag="$$base.$$n"; \
	done; \
	echo "Cutting $$tag from $$(git rev-parse --short HEAD)"; \
	git tag -a "$$tag" -m "release $$tag"; \
	git push origin "$$tag"; \
	echo "Pushed $$tag — follow: gh run watch \$$(gh run list --workflow=release --limit 1 --json databaseId --jq '.[0].databaseId')"

all: stage build test-install

clean:
	@rm -rf dist/ build/
	@echo "Cleaned."
