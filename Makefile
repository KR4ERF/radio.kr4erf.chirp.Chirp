# TODO:
# * Add multi-arch support

FLATPAK_APP_ID ?= radio.kr4erf.chirp.Chirp

FLATPAK_RUNTIME_PLATFORM ?= org.gnome.Platform
FLATPAK_RUNTIME_SDK ?= org.gnome.Sdk
FLATPAK_RUNTIME_VERSION ?= 49
FLATPAK_PLATFORM := $(FLATPAK_RUNTIME_PLATFORM)//$(FLATPAK_RUNTIME_VERSION)
FLATPAK_SDK := $(FLATPAK_RUNTIME_SDK)//$(FLATPAK_RUNTIME_VERSION)
WXPYTHON_VERSION ?= 4.2.5

FILES_DIR := ./files
PATCHES_DIR := ./patches
TEMPLATE_DIR := ./templates
SCRATCH_DIR := ./scratch

SCRATCH := $(abspath $(SCRATCH_DIR))
VENV_DIR := $(SCRATCH)/.venv
BUILD_CTX_DIR := $(SCRATCH)/buildctx
FLATPAK_FILES_DIR := $(BUILD_CTX_DIR)/files
FLATPAK_PATCHES_DIR := $(BUILD_CTX_DIR)/patches
FLATPAK_BUILD_DIR := $(BUILD_CTX_DIR)/build
FLATPAK_REPO_DIR := $(BUILD_CTX_DIR)/repo

BUNDLE := $(FLATPAK_APP_ID).flatpak
FLATPAK_BUNDLE := $(SCRATCH)/$(BUNDLE)
REPO_ARCHIVE := $(FLATPAK_APP_ID).repo.tar.zst
FLATPAK_REPO_ARCHIVE := $(SCRATCH)/$(REPO_ARCHIVE)

DEPS := curl envsubst flatpak flatpak-builder git gpg python3 sed gh
DEPS_VALIDATED := $(SCRATCH)/.deps-validated

PYTHON := $(VENV_DIR)/bin/python
PIP := $(PYTHON) -m pip


SCRATCH_STAMP := $(SCRATCH)/.stamp-scratch
PIP_STAMP := $(VENV_DIR)/.stamp-pip
COPY_STAMP := $(SCRATCH)/.stamp-copy

FLATPAK_BUILDER_TOOLS := https://github.com/flatpak/flatpak-builder-tools.git
FLATPAK_BUILDER_TOOLS_DIR := $(SCRATCH)/$(basename $(notdir $(FLATPAK_BUILDER_TOOLS)))
FLATPAK_BUILDER_PIP_TOOLS_DIR := $(FLATPAK_BUILDER_TOOLS_DIR)/pip
FLATPAK_PIP_GENERATOR_BIN := $(FLATPAK_BUILDER_PIP_TOOLS_DIR)/flatpak-pip-generator.py

CHIRP_REPO_URL := https://github.com/kk7ds/chirp.git
CHIRP_REPO_REF ?= master
CHIRP_REPO_COMMIT_FILE := $(SCRATCH)/.chirp_commit
CHIRP_REPO_COMMIT = $(strip $(file < $(CHIRP_REPO_COMMIT_FILE)))
CHIRP_REPO_COMMIT_SHORT = $(shell echo $(CHIRP_REPO_COMMIT) | awk '{print substr($$1,1,7)}')
CHIRP_REPO_TAG = $(CHIRP_REPO_REF).$(CHIRP_REPO_COMMIT_SHORT)
CHIRP_REQ_FILE_RAW := https://raw.githubusercontent.com/kk7ds/chirp/refs/heads/master/requirements.txt 
CHIRP_REQ_FILE := $(SCRATCH)/chirp-requirements.txt
FLATPAK_CHIRP_MODULE_FILE := $(BUILD_CTX_DIR)/chirp-requirements.yaml

FLATPAK_MANIFEST := $(FLATPAK_APP_ID).yaml
FLATPAK_MANIFEST_TEMPLATE := $(TEMPLATE_DIR)/$(FLATPAK_MANIFEST).template
FLATPAK_MANIFEST_FILE := $(BUILD_CTX_DIR)/$(FLATPAK_MANIFEST)

CHIRP_WRAPPER := ./chirpwx-wrapper.sh
CHIRP_BUILD_WRAPPER := $(BUILD_CTX_DIR)/$(CHIRP_WRAPPER)

FLATPAK_INSTALLATION ?= user

GH_OWNER ?= kr4erf
GH_RELEASE_URL ?= https://github.com/$(GH_OWNER)/$(FLATPAK_APP_ID)/releases/download/$(CHIRP_REPO_TAG)/$(REPO_ARCHIVE)
GH_TRIGGER_REPO ?= $(GH_OWNER)/$(GH_OWNER).github.io

.PHONY: help setup generate build install bundle archive release trigger clean

help:
	@echo "Usage:"
	@echo "  make setup       Gather needed files and runtimes"
	@echo "  make generate    Generate flatpak manifest"
	@echo "  make build       Create flatpak. Requires env: GPG_SIGNING_KEY"
	@echo "  make install     Install flatpak locally"
	@echo "  make bundle      Create flatpak bundle from build"
	@echo "  make archive     Create repo tarball from build"
	@echo "  make release     Upload bundle and repo archive to GitHub Releases. Requires env: GH_TOKEN"
	@echo "  make trigger     Trigger import on remote repository. Requires env: GH_TOKEN"
	@echo "  make clean       Clean the installation"

check-%:
	@if [ -z "$($*)" ]; then \
		echo "Error: $* is required"; \
		exit 1; \
	fi

$(SCRATCH_STAMP):
	mkdir --parents \
		$(SCRATCH) \
		$(VENV_DIR) \
		$(BUILD_CTX_DIR) \
		$(FLATPAK_FILES_DIR) \
		$(FLATPAK_PATCHES_DIR) \
		$(FLATPAK_BUILD_DIR) \
		$(FLATPAK_REPO_DIR)
	touch $@

$(DEPS_VALIDATED): $(SCRATCH_STAMP)
	@for d in $(DEPS); do \
		command -v $$d > /dev/null 2>&1 || { echo >&2 "$$d is missing"; exit 1; }; \
	done
	flatpak info --$(FLATPAK_INSTALLATION) --show-runtime --show-sdk $(FLATPAK_PLATFORM) > /dev/null 2>&1 || \
		{ \
			echo "$(FLATPAK_PLATFORM) or $(FLATPAK_SDK) not installed, installing..."; \
			flatpak install --$(FLATPAK_INSTALLATION) --noninteractive --runtime $(FLATPAK_PLATFORM); \
			flatpak install --$(FLATPAK_INSTALLATION) --noninteractive --runtime $(FLATPAK_SDK); \
		}
	touch $@

$(CHIRP_REPO_COMMIT_FILE): $(DEPS_VALIDATED)
	git ls-remote $(CHIRP_REPO_URL) refs/heads/$(CHIRP_REPO_REF) | awk '{print $$1}' > $@

$(PIP_STAMP): $(DEPS_VALIDATED)
	python3 -m venv $(VENV_DIR)
	$(PIP) install --upgrade pip
	touch $@

$(FLATPAK_PIP_GENERATOR_BIN): $(PIP_STAMP)
	git clone \
		--single-branch \
		--depth=1 \
		--filter=blob:none \
		--sparse \
		$(FLATPAK_BUILDER_TOOLS) $(FLATPAK_BUILDER_TOOLS_DIR)
	cd $(FLATPAK_BUILDER_TOOLS_DIR) && git sparse-checkout set pip
	$(PIP) install PyYAML
	$(PIP) install $(FLATPAK_BUILDER_PIP_TOOLS_DIR)

SRC_FILES := $(shell find $(FILES_DIR) $(PATCHES_DIR) -type f)

$(COPY_STAMP): $(SRC_FILES)
	mkdir -p $(FLATPAK_FILES_DIR) $(FLATPAK_PATCHES_DIR)
	cp -a $(FILES_DIR)/. $(FLATPAK_FILES_DIR)/
	cp -a $(PATCHES_DIR)/. $(FLATPAK_PATCHES_DIR)/
	touch $@

$(CHIRP_REQ_FILE): $(PIP_STAMP)
	curl --silent --show-error --location --output $(CHIRP_REQ_FILE) $(CHIRP_REQ_FILE_RAW)
	sed --in-place --regexp-extended '/(Windows|\!="Linux"|^#|wxPython)/d' $(CHIRP_REQ_FILE)
	echo "wxPython==$(WXPYTHON_VERSION)" >> $(CHIRP_REQ_FILE)

$(FLATPAK_MANIFEST_FILE): $(FLATPAK_MANIFEST_TEMPLATE) $(CHIRP_REPO_COMMIT_FILE)
	FLATPAK_APP_ID=$(FLATPAK_APP_ID) \
	FLATPAK_RUNTIME_PLATFORM=$(FLATPAK_RUNTIME_PLATFORM) \
	FLATPAK_RUNTIME_SDK=$(FLATPAK_RUNTIME_SDK) \
	FLATPAK_RUNTIME_VERSION=$(FLATPAK_RUNTIME_VERSION) \
	CHIRP_REPO_URL=$(CHIRP_REPO_URL) \
	CHIRP_REPO_COMMIT=$(CHIRP_REPO_COMMIT) \
	envsubst '$$FLATPAK_APP_ID $$FLATPAK_RUNTIME_PLATFORM $$FLATPAK_RUNTIME_SDK $$FLATPAK_RUNTIME_VERSION $$CHIRP_REPO_URL $$CHIRP_REPO_COMMIT' < $(FLATPAK_MANIFEST_TEMPLATE) > $(FLATPAK_MANIFEST_FILE)
	cp $(FLATPAK_MANIFEST_FILE) .

$(FLATPAK_CHIRP_MODULE_FILE): $(PIP_STAMP) $(FLATPAK_PIP_GENERATOR_BIN) $(CHIRP_REQ_FILE)
	$(PYTHON) $(FLATPAK_PIP_GENERATOR_BIN) \
		--runtime $(FLATPAK_SDK) \
		--requirements-file $(CHIRP_REQ_FILE) \
		--yaml \
		--checker-data \
		--output $(basename $@)
	sed -i '/^# Generated.*$$/d' $(FLATPAK_CHIRP_MODULE_FILE)
	cp $(FLATPAK_CHIRP_MODULE_FILE) .

setup: $(FLATPAK_PIP_GENERATOR_BIN) $(CHIRP_REQ_FILE) $(FLATPAK_MANIFEST_FILE) $(COPY_STAMP)

generate: $(FLATPAK_CHIRP_MODULE_FILE)

build: check-GPG_SIGNING_KEY setup generate
	cd $(BUILD_CTX_DIR) \
	&& flatpak-builder \
		--force-clean \
		--$(FLATPAK_INSTALLATION) \
		--gpg-sign=$(GPG_SIGNING_KEY) \
		--repo=$(FLATPAK_REPO_DIR) \
		$(FLATPAK_BUILD_DIR) \
		$(FLATPAK_MANIFEST_FILE)

bundle: check-GPG_SIGNING_KEY build
	gpg --export --armor $(GPG_SIGNING_KEY) | \
	flatpak build-bundle \
		--gpg-keys=- \
		$(FLATPAK_REPO_DIR) \
		$(FLATPAK_BUNDLE) \
		$(FLATPAK_APP_ID) \
		master

archive: build
	tar -c --zstd -f $(FLATPAK_REPO_ARCHIVE) -C $(BUILD_CTX_DIR) repo/

release: check-GH_TOKEN bundle archive
	gh release create "$(CHIRP_REPO_TAG)" \
		$(FLATPAK_BUNDLE) \
		$(FLATPAK_REPO_ARCHIVE) \
		--title "$(CHIRP_REPO_TAG)" \
		--notes "$$( \
			echo '=== Build Metadata ==='; \
			echo 'REPO: $(CHIRP_REPO_URL)'; \
			echo 'REF: $(CHIRP_REPO_REF)'; \
			echo 'COMMIT: $(CHIRP_REPO_COMMIT)'; \
			echo 'FLATPAK_PLATFORM: $(FLATPAK_PLATFORM)'; \
			echo 'FLATPAK_SDK: $(FLATPAK_SDK)'; \
			echo 'WXPYTHON_VERSION: $(WXPYTHON_VERSION)'; \
		)" \
		2> /dev/null \
	|| gh release upload "$(CHIRP_REPO_TAG)" \
		$(FLATPAK_BUNDLE) \
		$(FLATPAK_REPO_ARCHIVE) \
		--clobber

trigger: check-GH_TOKEN
	echo "Triggering import of $(GH_RELEASE_URL) into $(GH_TRIGGER_REPO)..."; \
	echo "{\"event_type\": \"import-flatpak\", \"client_payload\": {\"download_url\": \"$(GH_RELEASE_URL)\", \"app_id\": \"$(FLATPAK_APP_ID)\"}}" | \
	gh api --method POST /repos/$(GH_TRIGGER_REPO)/dispatches --input -

install: build
	flatpak install --$(FLATPAK_INSTALLATION) $(FLATPAK_REPO_DIR) $(FLATPAK_APP_ID)
	flatpak install --$(FLATPAK_INSTALLATION) $(FLATPAK_REPO_DIR) $(FLATPAK_APP_ID).Locale
	flatpak update --$(FLATPAK_INSTALLATION) $(FLATPAK_APP_ID)

clean:
	rm --recursive --force $(SCRATCH)
	rm --recursive --force ./.flatpak-builder
