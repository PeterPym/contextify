# Minimal helpers that delegate to scripts/xc.sh to avoid duplication.

.PHONY: build test clean hooks-setup setup

build:
	bash scripts/xc.sh build

test:
	bash scripts/xc.sh test

clean:
	rm -rf build/DerivedData build/DerivedData-beta

hooks-setup:
	@chmod +x .githooks/pre-commit || true
	@chmod +x scripts/xc.sh || true
	@git config core.hooksPath .githooks
	@echo "Git hooks enabled (core.hooksPath=.githooks). Pre-commit build guard active."

setup: hooks-setup build
	@echo "Setup complete. See build/logs/ for build output."
