# Minimal helpers that delegate to scripts/xc.sh to avoid duplication.

.PHONY: build test clean hooks-setup setup logs logs-live clean-db debug

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

# Log capture targets
logs:
	@bash scripts/capture-recent-logs.sh 5

logs-live:
	@bash scripts/stream-logs.sh /tmp/contextify-live.log

# Clean database for fresh testing
clean-db:
	@rm -f ~/Library/Application\ Support/Contextify/transcripts.db*
	@echo "Database cleared. Next launch will be fresh."

# Build with automatic log capture (30 seconds)
debug:
	@bash scripts/build-and-capture-logs.sh 30
