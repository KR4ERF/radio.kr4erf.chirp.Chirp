# TODO:
# * Add multi-arch support

FLATPAK_APP_ID ?= radio.kr4erf.chirp.Chirp

FLATPAK_RUNTIME_PLATFORM ?= org.gnome.Platform
FLATPAK_RUNTIME_SDK ?= org.gnome.Sdk
FLATPAK_RUNTIME_VERSION ?= 49
FLATPAK_PLATFORM := $(FLATPAK_RUNTIME_PLATFORM)//$(FLATPAK_RUNTIME_VERSION)
FLATPAK_SDK := $(FLATPAK_RUNTIME_SDK)//$(FLATPAK_RUNTIME_VERSION)
WXPYTHON_VERSION ?= 4.2.5

SCRATCH_DIR := ./scratch
SCRATCH := $(abspath $(SCRATCH_DIR))
SCRATCH_STAMP := $(SCRATCH)/.stamp
VENV_DIR := $(SCRATCH)/.venv
BUILD_CTX_DIR := $(SCRATCH)/buildctx
FLATPAK_BUILD_DIR := $(BUILD_CTX_DIR)/build
FLATPAK_REPO_DIR := $(BUILD_CTX_DIR)/repo

DEPS := curl envsubst flatpak flatpak-builder git python3 sed
DEPS_VALIDATED := $(SCRATCH)/.deps-validated

PYTHON := $(VENV_DIR)/bin/python
PIP := $(PYTHON) -m pip
PIP_STAMP := $(VENV_DIR)/.stamp

FLATPAK_BUILDER_TOOLS := https://github.com/flatpak/flatpak-builder-tools.git
FLATPAK_BUILDER_TOOLS_DIR := $(SCRATCH)/$(basename $(notdir $(FLATPAK_BUILDER_TOOLS)))
FLATPAK_BUILDER_PIP_TOOLS_DIR := $(FLATPAK_BUILDER_TOOLS_DIR)/pip
FLATPAK_PIP_GENERATOR_BIN := $(FLATPAK_BUILDER_PIP_TOOLS_DIR)/flatpak-pip-generator.py

CHIRP_REQ_FILE_RAW := https://raw.githubusercontent.com/kk7ds/chirp/refs/heads/master/requirements.txt 
CHIRP_REQ_FILE := $(SCRATCH)/chirp-requirements.txt
FLATPAK_CHIRP_MODULE_FILE := $(BUILD_CTX_DIR)/chirp-requirements.yaml

TEMPLATE_DIR := ./templates
FLATPAK_MANIFEST := $(FLATPAK_APP_ID).yaml
FLATPAK_MANIFEST_TEMPLATE := $(TEMPLATE_DIR)/$(FLATPAK_MANIFEST).template
FLATPAK_MANIFEST_FILE := $(BUILD_CTX_DIR)/$(FLATPAK_MANIFEST)

FLATPAK_INSTALLATION ?= user

check-%:
	@if [ -z "$($*)" ]; then \
		echo "Error: $* is required"; \
		exit 1; \
	fi

.PHONY: help setup generate build clean

help:
	@echo "Usage:"
	@echo "  make setup    Gather needed files and runtimes"
	@echo "  make generate Generate $(FLATPAK_CHIRP_MODULE_FILE)"
	@echo "  make build    Create flatpak"
	@echo "  make install  Install flatpak"
	@echo "  make clean    Clean the installation"

$(SCRATCH_STAMP):
	mkdir --parents \
		$(SCRATCH) \
		$(VENV_DIR) \
		$(BUILD_CTX_DIR) \
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

$(CHIRP_REQ_FILE): $(PIP_STAMP)
	curl --silent --show-error --location --output $(CHIRP_REQ_FILE) $(CHIRP_REQ_FILE_RAW)
	sed --in-place --regexp-extended '/(Windows|\!="Linux"|^#|wxPython)/d' $(CHIRP_REQ_FILE)
	echo "wxPython==$(WXPYTHON_VERSION)" >> $(CHIRP_REQ_FILE)

$(FLATPAK_MANIFEST_FILE): $(FLATPAK_MANIFEST_TEMPLATE)
	FLATPAK_APP_ID=$(FLATPAK_APP_ID) \
	FLATPAK_RUNTIME_PLATFORM=$(FLATPAK_RUNTIME_PLATFORM) \
	FLATPAK_RUNTIME_SDK=$(FLATPAK_RUNTIME_SDK) \
	FLATPAK_RUNTIME_VERSION=$(FLATPAK_RUNTIME_VERSION) \
	envsubst '$$FLATPAK_APP_ID $$FLATPAK_RUNTIME_PLATFORM $$FLATPAK_RUNTIME_SDK $$FLATPAK_RUNTIME_VERSION' < $(FLATPAK_MANIFEST_TEMPLATE) > $(FLATPAK_MANIFEST_FILE)
	cp $(FLATPAK_MANIFEST_FILE) .

$(FLATPAK_CHIRP_MODULE_FILE): $(PIP_STAMP) $(FLATPAK_PIP_GENERATOR_BIN) $(CHIRP_REQ_FILE)
	$(PYTHON) $(FLATPAK_PIP_GENERATOR_BIN) \
		--runtime $(FLATPAK_SDK) \
		--requirements-file $(CHIRP_REQ_FILE) \
		--yaml \
		--checker-data \
		--output $(basename $@)
	cp $(FLATPAK_CHIRP_MODULE_FILE) .

setup: $(FLATPAK_PIP_GENERATOR_BIN) $(CHIRP_REQ_FILE) $(FLATPAK_MANIFEST_FILE)

generate: $(FLATPAK_CHIRP_MODULE_FILE)

build: setup generate check-GPG_SIGNING_KEY
	cd $(BUILD_CTX_DIR) \
	&& flatpak-builder \
		--force-clean \
		--$(FLATPAK_INSTALLATION) \
		--gpg-sign=$(GPG_SIGNING_KEY) \
		--repo=$(FLATPAK_REPO_DIR) \
		$(FLATPAK_BUILD_DIR) \
		$(FLATPAK_MANIFEST_FILE)

install: build
	flatpak install --$(FLATPAK_INSTALLATION) $(FLATPAK_REPO_DIR) $(FLATPAK_APP_ID)

clean:
	rm --recursive --force $(SCRATCH)
	rm --recursive --force ./.flatpak-builder
