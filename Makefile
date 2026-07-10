SHELL := /bin/sh

VERSION := $(shell tr -d '\n' < VERSION)
ISO := dist/butopia-$(VERSION)-x86_64.iso

.DEFAULT_GOAL := help

.PHONY: help doctor check builder iso build smoke smoke-bios smoke-uefi run run-uefi clean builder-delete

help:
	@printf '%s\n' \
	  'Butopia Linux build commands' \
	  '' \
	  '  make doctor       Check the host and builder prerequisites' \
	  '  make check        Run fast repository validation' \
	  '  make builder      Create/start the isolated Linux builder VM' \
	  '  make iso          Build the signed x86_64 live/install ISO' \
	  '  make smoke        Boot-test the ISO through BIOS and UEFI' \
	  '  make run          Boot the ISO interactively through BIOS' \
	  '  make run-uefi     Boot the ISO interactively through UEFI' \
	  '  make clean        Remove local generated artifacts' \
	  '' \
	  'Live login: root (no password). Install with setup-butopia.'

doctor:
	@./scripts/doctor.sh

check:
	@./scripts/check.sh

builder:
	@./scripts/bootstrap-builder.sh

iso build: check
	@./scripts/build.sh

smoke: smoke-bios smoke-uefi

smoke-bios: $(ISO)
	@python3 tests/smoke_boot.py --iso "$(ISO)" --firmware bios --log dist/smoke-bios.log

smoke-uefi: $(ISO)
	@python3 tests/smoke_boot.py --iso "$(ISO)" --firmware uefi --log dist/smoke-uefi.log

run: $(ISO)
	@./scripts/run.sh "$(ISO)" bios

run-uefi: $(ISO)
	@./scripts/run.sh "$(ISO)" uefi

$(ISO):
	@printf 'Missing %s; run make iso first.\n' "$(ISO)" >&2
	@exit 1

clean:
	@rm -rf .build dist/*
	@mkdir -p dist
	@touch dist/.gitkeep

builder-delete:
	@./scripts/bootstrap-builder.sh --delete
