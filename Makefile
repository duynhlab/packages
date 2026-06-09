# duynhlab/packages — RPM SPEC mega-package builder
#
# Option A: single monorepo SPEC at specs/duynhlab.spec produces ONE RPM
# (duynhlab-<VERSION>-1.el9.x86_64.rpm) containing all 8 backends + frontend
# + CLI tools + nginx/valkey/postgresql config templates.

.PHONY: help all fetch-sources build-local build-local-all render-systemd \
        stage build smoke smoke-full publish-repo clean

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
	@echo "  smoke                      Install dist/*.rpm in Rocky 9 + verify"
	@echo "  smoke-full                 Full smoke: podman --systemd=always + Postgres sidecar"
	@echo "  publish-repo               Stage gh-pages YUM repo (build/gh-pages/)"
	@echo "  all                        stage + build + smoke"
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

smoke:
	@bash scripts/smoke-install.sh

smoke-full:
	@bash scripts/smoke-full.sh

publish-repo:
	@bash scripts/publish-yum-repo.sh

all: stage build smoke

clean:
	@rm -rf dist/ build/
	@echo "Cleaned."
